import Foundation
import Combine
import UserNotifications

@MainActor
final class RestStore: ObservableObject {
    @Published var preferences: Preferences { didSet { savePreferences(); updatePreviewVolume() } }
    @Published private(set) var session: RestSession?
    @Published private(set) var records: [RestRecord]
    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var errorMessage: String?
    @Published private(set) var routeName = L("尚未连接耳机")
    @Published private(set) var hasHeadphones = false
    @Published private(set) var now: Date
    @Published private(set) var notificationStatus = L("未开启")
    @Published private(set) var previewing: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var connectionMessage: String?
    private var connectionTask: Task<Void, Never>?
    private var connectionAttemptID: UUID?
    let audio: RestAudio
    private let defaults: UserDefaults
    private let clock: () -> Date
    private var timer: AnyCancellable?
    private var sessionPreferences: Preferences?
    private var previewTask: Task<Void, Never>?
    private let notificationsEnabled: Bool
    private let vibrate: () -> Void
    private var lastVibration: Date?
    private var resumeAlarmOnReconnect = false

    var remaining: TimeInterval { session?.remaining(at: now) ?? 0 }
    var totalMinutes: Int { records.filter(\.completed).reduce(0) { $0 + ($1.seconds ?? $1.minutes * 60) } / 60 }
    var completedCount: Int { records.filter(\.completed).count }
    var isTesting: Bool {
        #if DEBUG
        return audio is PreviewAudio
        #else
        return false
        #endif
    }

    /// 注入时钟、音频与本地存储，恢复被系统结束的会话时保持暂停。
    init(audio: RestAudio, defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init, runsTimer: Bool = true, notificationsEnabled: Bool = true, vibrate: @escaping () -> Void = {}) {
        self.theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .forest
        self.vibrate = vibrate
        self.audio = audio
        self.defaults = defaults
        self.clock = clock
        self.notificationsEnabled = notificationsEnabled
        now = clock()
        var loaded = Self.decode(Preferences.self, key: "preferences", defaults: defaults) ?? Preferences()
        if loaded.presets == [15, 25, 45, 90] { loaded.presets = [15, 30, 45, 60] }
        loaded.normalize()
        preferences = loaded
        records = Self.decode([RestRecord].self, key: "records", defaults: defaults) ?? []
        if var restored = Self.decode(RestSession.self, key: "session", defaults: defaults) {
            if restored.phase == .resting || restored.phase == .ringing {
                restored.pause(at: min(clock(), restored.deadline), reason: L("应用恢复"))
            }
            restored.restingSince = nil
            restored.phase = .blocked
            restored.reason = L("应用曾被关闭或系统结束，提醒未在后台继续。请确认耳机后手动恢复。")
            session = restored
            sessionPreferences = Self.decode(Preferences.self, key: "sessionPreferences", defaults: defaults) ?? loaded
        }
        refreshRoute()
        audio.onSafetyStop = { [weak self] reason, disconnected in self?.block(reason, disconnected: disconnected) }
        audio.onRouteUpdate = { [weak self] in self?.handleRouteUpdate() }
        if runsTimer {
            timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        }
        if notificationsEnabled { refreshNotifications() }
    }

    /// 仅在耳机可用且无会话时启动，音频成功后才提交计时状态。
    func start(duration: TimeInterval? = nil) {
        guard session == nil else { return }
        cancelConnectionAttempt()
        stopPreview()
        now = clock()
        let duration = duration ?? preferences.durationSeconds
        guard duration.isFinite, duration >= 1, duration <= 86400 else {
            errorMessage = L("请选择有效的提醒时间。")
            return
        }
        do {
            try audio.start(preferences: preferences, remaining: duration)
            session = RestSession(now: now, duration: duration)
            sessionPreferences = preferences
            persistSession()
            scheduleNotification()
        } catch { errorMessage = error.localizedDescription }
        refreshRoute()
    }

    /// 使用本轮固定的响铃配置刷新倒计时，只有限时提醒会自动结束。
    func tick() {
        guard var current = session else { return }
        now = clock()
        let oldPhase = current.phase
        let shouldEnd = current.tick(at: now, repeatAlarm: (sessionPreferences ?? preferences).repeatAlarm)
        session = current
        if current.phase == .ringing {
            (audio as? HeadphoneAudio)?.stopAmbienceIfRinging()
            if (sessionPreferences ?? preferences).vibrationEnabled,
               lastVibration.map({ now.timeIntervalSince($0) >= 2 }) ?? true {
                vibrate()
                lastVibration = now
            }
        }
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

    /// 恢复时重新验证耳机，失败时保留暂停状态；响铃重连由会话策略触发。
    func resume() {
        guard var current = session, [.paused, .blocked].contains(current.phase) else { return }
        now = clock()
        current.resume(at: now)
        do {
            try audio.start(preferences: sessionPreferences ?? preferences, remaining: current.remaining(at: now))
            session = current
            resumeAlarmOnReconnect = false
            lastVibration = nil
            persistSession()
            if current.phase == .resting { scheduleNotification() }
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
        } catch {
            block(error.localizedDescription)
        }
    }

    /// 结束会话仅写入一次记录，同时清除音频、预约和恢复快照。
    func finish(completed: Bool) {
        guard let current = session else { return }
        resumeAlarmOnReconnect = false
        lastVibration = nil
        audio.stop()
        cancelNotification()
        let end = clock()
        records.insert(RestRecord(id: current.id, startedAt: current.startedAt, endedAt: end,
                                  minutes: max(0, Int(current.restedSeconds(at: end) / 60)),
                                  completed: completed, sound: (sessionPreferences ?? preferences).sleepSound,
                                  seconds: max(0, Int(current.restedSeconds(at: end)))), at: 0)
        records = Array(records.prefix(365))
        encode(records, key: "records")
        session = nil
        sessionPreferences = nil
        persistSession()
    }

    /// 安全事件立即停止音轨；仅响铃阶段断连允许限时自动续响。
    func block(_ reason: String, disconnected: Bool = false) {
        if isConnecting {
            cancelConnectionAttempt()
            connectionMessage = reason
        }
        previewTask?.cancel()
        previewing = nil
        audio.stop()
        guard var current = session else { return }
        now = clock()
        resumeAlarmOnReconnect = (current.phase == .ringing || (current.phase == .resting && now >= current.deadline)) && disconnected
        let reconnectReason = (sessionPreferences ?? preferences).repeatAlarm
            ? L("耳机已断开，响铃已停止。重新连接后将尝试继续重复响铃。")
            : L("耳机已断开，响铃已停止。三分钟内重新连接后将尝试自动续响。")
        current.pause(at: now, reason: resumeAlarmOnReconnect ? reconnectReason : reason)
        session = current
        persistSession()
        cancelNotification()
        refreshRoute()
    }

    /// 耳机内试听十五秒；再次点击同一声音停止，不创建闹钟或通知。
    func preview(name: String, volume: Float) throws {
        guard session == nil else { return }
        cancelConnectionAttempt()
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

    /// 配置变化即时传递至当前试听音轨，分别使用助眠和提醒增益。
    private func updatePreviewVolume() {
        guard let previewing else { return }
        let isAlarm = previewing.hasPrefix("custom-alarm.") || AlarmSound.allCases.contains { $0.rawValue == previewing }
        audio.updatePreviewVolume(isAlarm ? preferences.alarmVolume : preferences.sleepVolume)
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

    /// 在用户操作后无声激活路由，并等待蓝牙路由通知刷新界面。
    func reconnectHeadphones() {
        guard !isConnecting else { return }
        do { try audio.refreshConnection() } catch { errorMessage = error.localizedDescription }
        handleRouteUpdate()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.handleRouteUpdate()
        }
    }

    /// 最多十二秒尝试系统自动切换，只有真实耳机路由才允许播放确认音。
    func attemptHeadphoneConnection(timeout: TimeInterval = 12, confirmationDuration: TimeInterval = 2) {
        guard session == nil, !isConnecting else { return }
        stopPreview()
        let id = UUID()
        connectionAttemptID = id
        isConnecting = true
        connectionMessage = L("正在尝试连接耳机…")
        do { try audio.beginConnectionAttempt() }
        catch {
            cancelConnectionAttempt()
            connectionMessage = error.localizedDescription
            return
        }
        guard connectionAttemptID == id else { return }
        connectionTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(timeout)
            while !Task.isCancelled {
                guard let self, self.connectionAttemptID == id else { return }
                self.refreshRoute()
                if self.hasHeadphones {
                    do {
                        try self.audio.playConnectionConfirmation()
                        self.connectionMessage = L("已连接，正在耳机内播放轻柔提示音。")
                        try await Task.sleep(for: .seconds(confirmationDuration))
                        guard !Task.isCancelled, self.connectionAttemptID == id else { return }
                        self.cancelConnectionAttempt()
                        self.refreshRoute()
                        self.connectionMessage = self.hasHeadphones ? L("耳机已连接，可以开始休息。") : L("耳机已断开，声音已停止。")
                    } catch {
                        guard !Task.isCancelled, self.connectionAttemptID == id else { return }
                        self.cancelConnectionAttempt()
                        self.connectionMessage = error.localizedDescription
                    }
                    return
                }
                if Date() >= deadline {
                    self.cancelConnectionAttempt()
                    self.refreshRoute()
                    self.connectionMessage = L("暂未切换成功。请点右侧输出按钮重新选择 AirPods，或在控制中心选择耳机后再试。")
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// 同步停止连接探测及确认音，取消的任务不能再影响后续休息播放。
    func cancelConnectionAttempt() {
        guard isConnecting else { return }
        connectionAttemptID = nil
        connectionTask?.cancel()
        connectionTask = nil
        isConnecting = false
        connectionMessage = nil
        audio.stop()
        refreshRoute()
    }

    /// 连接探测仅限前台；真实助眠播放和提醒沿用后台音频会话。
    func enteredBackground() { cancelConnectionAttempt() }

    /// 持续响铃没有三分钟续响上限，限时模式保留原有恢复窗口。
    private var canResumeAlarm: Bool {
        guard let session else { return false }
        return (sessionPreferences ?? preferences).repeatAlarm || clock().timeIntervalSince(session.deadline) < 180
    }

    /// 响铃期间断连后仅在真实耳机重连时续响，休息阶段保持手动恢复。
    private func handleRouteUpdate() {
        refreshRoute()
        if resumeAlarmOnReconnect && hasHeadphones {
            if canResumeAlarm { resume() }
            else { resumeAlarmOnReconnect = false }
        }
    }

    /// 前台恢复时核对路由，避免界面仍显示已连接或运行状态。
    func becameActive() {
        refreshRoute()
        if let current = session, [.resting, .ringing].contains(current.phase), !hasHeadphones {
            block(L("当前没有可用耳机，声音已停止。连接后请手动继续。"), disconnected: true)
        }
        if resumeAlarmOnReconnect && hasHeadphones {
            if canResumeAlarm { resume() }
            else { resumeAlarmOnReconnect = false }
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

    /// 保存精确到秒的自定义预设，整分钟沿用已有预设并保持去重。
    func addDurationPreset(_ seconds: Int) {
        guard (1...43200).contains(seconds) else { return }
        if seconds % 60 == 0 { addPreset(seconds / 60) }
        else if !preferences.precisePresets.contains(seconds) {
            preferences.precisePresets.append(seconds)
            preferences.precisePresets.sort()
        }
    }

    /// 删除一个精确时长，不改变当前选中值。
    func removeDurationPreset(_ seconds: Int) {
        if seconds % 60 == 0 { removePreset(seconds / 60) }
        else { preferences.precisePresets.removeAll { $0 == seconds } }
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
            } catch { errorMessage = LF("无法开启静默通知：%@", String(describing: error.localizedDescription)) }
        }
    }

    /// 读取通知状态，拒绝时保持耳机内提醒可用。
    private func refreshNotifications() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) ? L("已开启 · 无铃声") : L("未开启")
        }
    }

    /// 使用无声本地通知显示到点提醒，不使用系统闹钟或通知铃声兜底。
    private func scheduleNotification() {
        guard notificationsEnabled, let current = session, current.deadline > clock() else { return }
        let content = UNMutableNotificationContent()
        content.title = L("休息好啦，慢慢醒来")
        content.body = L("伸个懒腰，给自己一点时间。打开耳憩，结束休息或再睡一会儿。")
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
