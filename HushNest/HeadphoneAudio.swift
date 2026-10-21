import AVFoundation

@MainActor
protocol RestAudio: AnyObject {
    var isHeadphoneConnected: Bool { get }
    var routeName: String { get }
    var onSafetyStop: ((String, Bool) -> Void)? { get set }
    var onRouteUpdate: (() -> Void)? { get set }
    /// 无声激活会话并刷新系统路由。
    func refreshConnection() throws
    /// 用户确认后短暂启动零音量媒体，尝试请求系统切换耳机。
    func beginConnectionAttempt() throws
    /// 实际路由确认后在耳机内播放低音量提示。
    func playConnectionConfirmation() throws
    /// 在验证耳机路由后开始助眠音及按设备时钟预约的提醒。
    func start(preferences: Preferences, remaining: TimeInterval) throws
    /// 在耳机内短暂试听指定音轨，不创建计时会话。
    func preview(name: String, volume: Float) throws
    /// 即时修改试听播放器音量，不重启或重置进度。
    func updatePreviewVolume(_ volume: Float)
    /// 立即停止两条音轨并释放音频会话。
    func stop()
}

enum AudioFailure: LocalizedError {
    case noHeadphones, missingResource, playbackFailed, customMissing
    var errorDescription: String? {
        switch self {
        case .customMissing: L("自定义音轨无法读取，请重新导入或选择内置声音。")
        case .noHeadphones: L("请先连接有线耳机或蓝牙耳机。手机扬声器不会用于提醒。")
        case .missingResource: L("声音资源无法读取，请重新安装应用。")
        case .playbackFailed: L("音频会话未能启动，请检查耳机连接后重试。")
        }
    }
}

@MainActor
final class HeadphoneAudio: NSObject, RestAudio {
    private let session = AVAudioSession.sharedInstance()
    private var ambience: AVAudioPlayer?
    private var alarm: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private var active = false
    private var connecting = false
    var onSafetyStop: ((String, Bool) -> Void)?
    var onRouteUpdate: (() -> Void)?

    var isHeadphoneConnected: Bool { Self.allOutputsArePrivate(session.currentRoute.outputs.map(\.portType)) }
    var routeName: String { isHeadphoneConnected ? session.currentRoute.outputs.map(\.portName).joined(separator: "、") : L("尚未连接耳机") }

    /// 只接受明确的耳机输出，并拒绝任何包含扬声器、车载或 AirPlay 的混合路由。
    static func allOutputsArePrivate(_ outputs: [AVAudioSession.Port]) -> Bool {
        !outputs.isEmpty && outputs.allSatisfy { [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains($0) }
    }

    /// 注册路由、中断与媒体服务重置监听，禁止自动恢复到手机扬声器。
    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.began.rawValue {
                let reason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                let disconnected = reason == AVAudioSession.InterruptionReason.routeDisconnected.rawValue
                MainActor.assumeIsolated {
                    self?.safetyStop(disconnected ? L("耳机已断开，声音已停止。") : L("音频被来电或其他应用中断，请确认耳机后手动继续。"), disconnected: disconnected)
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.safetyStop(L("系统音频服务已重置，请重新连接耳机并继续。")) }
        })

    }

    /// 启动真实可听的助眠播放，并预约提醒，前后两次检查耳机路由。
    func start(preferences: Preferences, remaining: TimeInterval) throws {
        stop()
        do {
            try activateHeadphones()
            let sleepPlayer = preferences.sleepSound == .none ? nil : try player(named: preferences.sleepSound == .custom ? "custom-sleep.\(preferences.customSleepID?.uuidString ?? "")" : preferences.sleepSound.rawValue)
            let alarmPlayer = try prepareAlarm(preferences: preferences)
            sleepPlayer?.numberOfLoops = -1
            sleepPlayer?.volume = preferences.sleepVolume
            ambience = sleepPlayer
            alarm = alarmPlayer
            active = true
            guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
            if remaining > 0 {
                guard (sleepPlayer?.play() ?? true), alarmPlayer.play(atTime: alarmPlayer.deviceCurrentTime + remaining) else { throw AudioFailure.playbackFailed }
            } else {
                guard alarmPlayer.play() else { throw AudioFailure.playbackFailed }
            }
        } catch {
            stop()
            throw error
        }
    }

    /// 准备真实铃声播放器但不播放，持续提醒对内置及自定义音轨都使用无限循环。
    func prepareAlarm(preferences: Preferences) throws -> AVAudioPlayer {
        let name = preferences.alarmSound == .custom ? "custom-alarm.\(preferences.customAlarmID?.uuidString ?? "")" : preferences.alarmSound.rawValue
        let player = try player(named: name)
        player.numberOfLoops = preferences.repeatAlarm ? -1 : 2
        player.volume = preferences.alarmVolume
        alarm = player
        return player
    }

    /// 试听沿用同一耳机门禁和断连保护，任何启动错误均停止音频。
    func preview(name: String, volume: Float) throws {
        stop()
        do {
            try activateHeadphones()
            let preview = try preparePreview(name: name, volume: volume)
            active = true
            guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
            guard preview.play() else { throw AudioFailure.playbackFailed }
        } catch {
            stop()
            throw error
        }
    }

    /// 准备试听播放器但不播放，用于先加载资源再执行耳机门禁。
    func preparePreview(name: String, volume: Float) throws -> AVAudioPlayer {
        let preview = try player(named: name)
        preview.volume = min(1, max(0.01, volume))
        ambience = preview
        return preview
    }

    /// 调整现有播放器增益，滑动时立即生效且不从头播放。
    func updatePreviewVolume(_ volume: Float) { ambience?.volume = min(1, max(0.01, volume)) }

    /// 手动刷新时只激活混音会话，不播放探测音，也不申请麦克风权限。
    func refreshConnection() throws {
        guard !active else { onRouteUpdate?(); return }
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        onRouteUpdate?()
    }

    /// 仅在用户确认后临时申请独占媒体会话，路由未确认前播放器始终为零音量。
    func beginConnectionAttempt() throws {
        stop()
        do {
            connecting = true
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPrefersInterruptionOnRouteDisconnect(true)
            try session.setActive(true)
            let probe = try player(named: "piano")
            probe.volume = 0
            probe.numberOfLoops = -1
            ambience = probe
            guard probe.play() else { throw AudioFailure.playbackFailed }
        } catch {
            stop()
            throw error
        }
    }

    /// 复用探测播放器，只有真实耳机输出才允许两秒轻柔确认音。
    func playConnectionConfirmation() throws {
        guard connecting, let player = ambience, isHeadphoneConnected else { throw AudioFailure.noHeadphones }
        connecting = false
        active = true
        player.currentTime = 0
        player.numberOfLoops = 0
        guard isHeadphoneConnected else { stop(); throw AudioFailure.noHeadphones }
        player.setVolume(0.12, fadeDuration: 0.4)
    }

    /// 先激活系统媒体路由，再检查耳机；不抢占其他应用的音乐。
    private func activateHeadphones() throws {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPrefersInterruptionOnRouteDisconnect(true)
        try session.setActive(true)
        guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
    }

    /// 提醒开始后停止助眠音，避免两条音轨叠加。
    func stopAmbienceIfRinging() { ambience?.stop() }

    /// 在停止后清除预约音轨，不留下可外放的通知声音。
    func stop() {
        active = false
        connecting = false
        ambience?.volume = 0
        ambience?.stop()
        alarm?.stop()
        ambience = nil
        alarm = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 从应用内读取原创合成音频，不需要网络或麦克风权限。
    private func player(named name: String) throws -> AVAudioPlayer {
        let url: URL
        if name.hasPrefix("custom-") {
            let parts = name.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { throw AudioFailure.customMissing }
            url = MediaLibrary.directory.appendingPathComponent(id.uuidString + (parts[0] == "custom-alarm" ? "-alarm.m4a" : ".m4a"))
            guard FileManager.default.fileExists(atPath: url.path) else { throw AudioFailure.customMissing }
        } else {
            guard let resource = Bundle.main.url(forResource: name, withExtension: "wav") else { throw AudioFailure.missingResource }
            url = resource
        }
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }

    /// 输出变化时立即关闭非耳机播放，并通知会话层判断重连续响。
    private func routeChanged() {
        if active && !isHeadphoneConnected { safetyStop(L("耳机已断开，声音已停止。重新连接后请手动继续。"), disconnected: true) }
        onRouteUpdate?()
    }

    /// 统一执行安全停止，并通知会话层标记中断。
    private func safetyStop(_ reason: String, disconnected: Bool = false) {
        guard active || connecting else { onRouteUpdate?(); return }
        stop()
        onSafetyStop?(reason, disconnected)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

#if DEBUG
@MainActor
final class PreviewAudio: RestAudio {
    var isHeadphoneConnected = true
    var routeName: String { isHeadphoneConnected ? L("测试耳机（无声模拟）") : L("尚未连接耳机") }
    var onSafetyStop: ((String, Bool) -> Void)?
    var onRouteUpdate: (() -> Void)?
    var starts = 0
    var previews = 0
    var stops = 0
    var previewVolume: Float = 0
    var failure: Error?
    var connectionAttempts = 0
    var connectionConfirmations = 0

    /// 无声替身只刷新可观察连接状态。
    func refreshConnection() throws { onRouteUpdate?() }
    /// 记录主动连接请求，始终保持无声且不模拟虚假成功。
    func beginConnectionAttempt() throws {
        if let failure { throw failure }
        connectionAttempts += 1
    }
    /// 仅在模拟路由真实为耳机时记录确认音请求。
    func playConnectionConfirmation() throws {
        guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
        connectionConfirmations += 1
    }
    /// 测试替身仅记录启动，不访问任何音频设备。
    func start(preferences: Preferences, remaining: TimeInterval) throws {
        guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
        if let failure { throw failure }
        starts += 1
    }
    /// 无声验证试听门禁，不向模拟器或 Mac 输出声音。
    func preview(name: String, volume: Float) throws {
        guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
        if let failure { throw failure }
        previews += 1
        previewVolume = volume
    }
    /// 记录实时增益，验证 UI 调节确实传递至音频层。
    func updatePreviewVolume(_ volume: Float) { previewVolume = volume }
    /// 记录停止次数以验证断连和暂停的行为。
    func stop() { stops += 1 }
    /// 注入断连事件，验证会话立即阻止播放。
    func disconnect() {
        isHeadphoneConnected = false
        onSafetyStop?(L("耳机已断开，声音已停止。重新连接后请手动继续。"), true)
        onRouteUpdate?()
    }
    /// 注入重连事件，由会话层根据阶段决定是否续响。
    func reconnect() { isHeadphoneConnected = true; onRouteUpdate?() }
}
#endif
