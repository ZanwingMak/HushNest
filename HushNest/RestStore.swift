import Foundation
import Combine
import UserNotifications

@MainActor
final class RestStore: ObservableObject {
    @Published var preferences: Preferences { didSet { savePreferences() } }
    @Published private(set) var session: RestSession?
    @Published private(set) var records: [RestRecord]
    @Published var errorMessage: String?
    @Published private(set) var routeName = "尚未连接耳机"
    @Published private(set) var hasHeadphones = false
    @Published private(set) var now: Date
    @Published private(set) var notificationStatus = "未开启"
    @Published private(set) var previewing: String?
    let audio: RestAudio
    private let defaults: UserDefaults
    private let clock: () -> Date
    private var timer: AnyCancellable?
    private var sessionPreferences: Preferences?
    private var previewTask: Task<Void, Never>?
    private let notificationsEnabled: Bool

    var remaining: TimeInterval { session?.remaining(at: now) ?? 0 }
    var totalMinutes: Int { records.filter(\.completed).reduce(0) { $0 + $1.minutes } }
    var completedCount: Int { records.filter(\.completed).count }
    var isTesting: Bool {
        #if DEBUG
        return audio is PreviewAudio
        #else
        return false
        #endif
    }

    /// 注入时钟、音频与本地存储，恢复被系统结束的会话时保持暂停。
    init(audio: RestAudio, defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init, runsTimer: Bool = true, notificationsEnabled: Bool = true) {
        self.audio = audio
        self.defaults = defaults
        self.clock = clock
        self.notificationsEnabled = notificationsEnabled
        now = clock()
        var loaded = Self.decode(Preferences.self, key: "preferences", defaults: defaults) ?? Preferences()
        loaded.normalize()
        preferences = loaded
        records = Self.decode([RestRecord].self, key: "records", defaults: defaults) ?? []
        if var restored = Self.decode(RestSession.self, key: "session", defaults: defaults) {
            if restored.phase == .resting || restored.phase == .ringing {
                restored.pause(at: min(clock(), restored.deadline), reason: "应用恢复")
            }
            restored.restingSince = nil
            restored.phase = .blocked
            restored.reason = "应用曾被关闭或系统结束，提醒未在后台继续。请确认耳机后手动恢复。"
            session = restored
            sessionPreferences = Self.decode(Preferences.self, key: "sessionPreferences", defaults: defaults) ?? loaded
        }
        refreshRoute()
        audio.onSafetyStop = { [weak self] reason in self?.block(reason) }
        audio.onRouteUpdate = { [weak self] in self?.refreshRoute() }
        audio.onPause = { [weak self] in
            guard let self else { return }
            if self.session?.phase == .resting { self.pause() }
            else if self.session?.phase == .ringing { self.block("你已暂停唤醒铃声，请回到应用手动继续或结束休息。") }
            else { self.stopPreview() }
        }
        if runsTimer {
            timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        }
        if notificationsEnabled { refreshNotifications() }
    }

    /// 仅在耳机可用且无会话时启动，音频成功后才提交计时状态。
    func start(duration: TimeInterval? = nil) {
        guard session == nil else { return }
        stopPreview()
        now = clock()
        let duration = duration ?? TimeInterval(preferences.minutes * 60)
        guard duration.isFinite, duration >= 1, duration <= 86400 else {
            errorMessage = "请选择有效的提醒时间。"
            return
        }
        do {
            try audio.start(preferences: preferences, remaining: duration)
            session = RestSession(now: now, duration: duration)
            sessionPreferences = preferences
            persistSession()
            scheduleNotification()
            updateLockScreen()
        } catch { errorMessage = error.localizedDescription }
        refreshRoute()
    }

    /// 使用绝对时间刷新倒计时，响铃三分钟后自动结束，防止持续占用耳机。
    func tick() {
        guard var current = session else { return }
        now = clock()
        let oldPhase = current.phase
        let shouldEnd = current.tick(at: now)
        session = current
        if current.phase == .ringing { (audio as? HeadphoneAudio)?.stopAmbienceIfRinging() }
        if oldPhase != current.phase { persistSession() }
        if shouldEnd { finish(completed: true) }
    }

    /// 手动暂停同时撤销预约音轨和静默通知，并冻结剩余时间。
    func pause() {
        guard var current = session, current.phase == .resting else { return }
        now = clock()
        current.pause(at: now)
        audio.stop()
        session = current
        persistSession()
        cancelNotification()
    }

    /// 用户明确继续时重新验证耳机，失败时保留原有暂停状态。
    func resume() {
        guard var current = session, [.paused, .blocked].contains(current.phase) else { return }
        now = clock()
        current.resume(at: now)
        do {
            try audio.start(preferences: sessionPreferences ?? preferences, remaining: current.remaining(at: now))
            session = current
            persistSession()
            if current.phase == .resting { scheduleNotification() }
            updateLockScreen()
        } catch { errorMessage = error.localizedDescription }
        refreshRoute()
    }

    /// 响铃期间执行稍后提醒，音频预约失败则进入明确的中断状态。
    func snooze() {
        guard var current = session, current.phase == .ringing else { return }
        now = clock()
        let settings = sessionPreferences ?? preferences
        current.snooze(at: now, minutes: settings.snoozeMinutes)
        do {
            try audio.start(preferences: settings, remaining: current.remaining(at: now))
            session = current
            persistSession()
            scheduleNotification()
            updateLockScreen()
        } catch {
            block(error.localizedDescription)
        }
    }

    /// 结束会话仅写入一次记录，同时清除音频、预约和恢复快照。
    func finish(completed: Bool) {
        guard let current = session else { return }
        audio.stop()
        cancelNotification()
        let end = clock()
        records.insert(RestRecord(id: current.id, startedAt: current.startedAt, endedAt: end,
                                  minutes: max(0, Int(current.restedSeconds(at: end) / 60)),
                                  completed: completed, sound: (sessionPreferences ?? preferences).sleepSound), at: 0)
        records = Array(records.prefix(365))
        encode(records, key: "records")
        session = nil
        sessionPreferences = nil
        persistSession()
    }

    /// 安全事件立即停止音轨，保留原截止时间且禁止重连自动恢复。
    func block(_ reason: String) {
        previewTask?.cancel()
        previewing = nil
        audio.stop()
        guard var current = session else { return }
        now = clock()
        current.pause(at: now, reason: reason)
        session = current
        persistSession()
        cancelNotification()
        refreshRoute()
    }

    /// 耳机内试听十五秒；再次点击同一声音停止，不创建闹钟或通知。
    func preview(name: String, volume: Float) throws {
        guard session == nil else { return }
        if previewing == name { stopPreview(); return }
        stopPreview()
        try audio.preview(name: name, volume: volume)
        previewing = name
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.stopPreview()
        }
    }

    /// 关闭配置页或开始休息时停止试听，避免遗留背景播放。
    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        guard previewing != nil else { return }
        previewing = nil
        audio.stop()
    }

    /// 刷新当前真实输出设备名称和连接状态。
    func refreshRoute() {
        routeName = audio.routeName
        hasHeadphones = audio.isHeadphoneConnected
    }

    /// 前台恢复时核对路由，避免界面仍显示已连接或运行状态。
    func becameActive() {
        refreshRoute()
        if let current = session, [.resting, .ringing].contains(current.phase), !hasHeadphones {
            block("当前没有可用耳机，声音已停止。连接后请手动继续。")
        }
        tick()
        if notificationsEnabled { refreshNotifications() }
    }

    /// 预设去重并限制范围，所有数量均免费开放。
    func addPreset(_ minutes: Int) {
        guard (1...720).contains(minutes), !preferences.presets.contains(minutes) else { return }
        preferences.presets.append(minutes)
        preferences.presets.sort()
    }

    /// 删除指定预设，不改变已选时长。
    func removePreset(_ minutes: Int) { preferences.presets.removeAll { $0 == minutes } }

    /// 清空本机记录，不影响进行中的会话或预设。
    func clearHistory() { records = []; encode(records, key: "records") }

    /// 仅在用户开启静默通知时申请权限，通知不携带任何声音资源。
    func requestNotifications() {
        guard notificationsEnabled else { return }
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])
                refreshNotifications()
                if session?.phase == .resting { scheduleNotification() }
            } catch { errorMessage = "无法开启静默通知：\(error.localizedDescription)" }
        }
    }

    /// 读取通知状态，拒绝时保持耳机内提醒可用。
    private func refreshNotifications() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) ? "已开启 · 无铃声" : "未开启"
        }
    }

    /// 使用无声本地通知显示到点提醒，不使用系统闹钟或通知铃声兜底。
    private func scheduleNotification() {
        guard notificationsEnabled, let current = session, current.deadline > clock() else { return }
        let content = UNMutableNotificationContent()
        content.title = "耳憩 · 休息时间到了"
        content.body = "耳机提醒依赖仍在运行的助眠音频。打开耳憩查看当前状态。"
        content.sound = nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, current.deadline.timeIntervalSince(clock())), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rest-deadline", content: content, trigger: trigger))
    }

    /// 撤销本应用的静默预约和已展示通知。
    private func cancelNotification() {
        guard notificationsEnabled else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest-deadline"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["rest-deadline"])
    }

    /// 更新锁屏元数据，让用户知道当前助眠会话的截止时间。
    private func updateLockScreen() {
        guard let session else { return }
        audio.updateNowPlaying(deadline: session.deadline, duration: session.duration)
    }

    /// 保存完整配置，应用重启后恢复用户选择。
    private func savePreferences() { encode(preferences, key: "preferences") }

    /// 保存会话快照及其固定配置，避免运行时编辑影响本轮提醒。
    private func persistSession() {
        encode(session, key: "session")
        encode(sessionPreferences, key: "sessionPreferences")
    }

    /// 将小体积本地数据编码至 UserDefaults，不记录任何身份数据。
    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    /// 读取可选持久化数据，损坏时由调用方采用安全默认值。
    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
