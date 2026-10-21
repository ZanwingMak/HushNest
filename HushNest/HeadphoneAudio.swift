import AVFoundation
import MediaPlayer

@MainActor
protocol RestAudio: AnyObject {
    var isHeadphoneConnected: Bool { get }
    var routeName: String { get }
    var onSafetyStop: ((String) -> Void)? { get set }
    var onRouteUpdate: (() -> Void)? { get set }
    var onPause: (() -> Void)? { get set }
    /// 在验证耳机路由后开始助眠音及按设备时钟预约的提醒。
    func start(preferences: Preferences, remaining: TimeInterval) throws
    /// 在耳机内短暂试听指定音轨，不创建计时会话。
    func preview(name: String, volume: Float) throws
    /// 立即停止两条音轨并释放音频会话。
    func stop()
    /// 更新锁屏上的剩余时间和播放信息。
    func updateNowPlaying(deadline: Date, duration: TimeInterval)
}

enum AudioFailure: LocalizedError {
    case noHeadphones, missingResource, playbackFailed
    var errorDescription: String? {
        switch self {
        case .noHeadphones: "请先连接有线耳机或蓝牙耳机。手机扬声器不会用于提醒。"
        case .missingResource: "声音资源无法读取，请重新安装应用。"
        case .playbackFailed: "音频会话未能启动，请检查耳机连接后重试。"
        }
    }
}

@MainActor
final class HeadphoneAudio: NSObject, RestAudio {
    private let session = AVAudioSession.sharedInstance()
    private var ambience: AVAudioPlayer?
    private var alarm: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var active = false
    var onSafetyStop: ((String) -> Void)?
    var onRouteUpdate: (() -> Void)?
    var onPause: (() -> Void)?

    var isHeadphoneConnected: Bool { Self.allOutputsArePrivate(session.currentRoute.outputs.map(\.portType)) }
    var routeName: String { isHeadphoneConnected ? session.currentRoute.outputs.map(\.portName).joined(separator: "、") : "尚未连接耳机" }

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
                MainActor.assumeIsolated { self?.safetyStop("音频被来电或其他应用中断，请确认耳机后手动继续。") }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.safetyStop("系统音频服务已重置，请重新连接耳机并继续。") }
        })
        for command in [MPRemoteCommandCenter.shared().pauseCommand, MPRemoteCommandCenter.shared().togglePlayPauseCommand] {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in self?.onPause?() }
                return .success
            }
            remoteTargets.append((command, target))
        }
        MPRemoteCommandCenter.shared().playCommand.isEnabled = false
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
    }

    /// 启动真实可听的助眠播放，并预约提醒，前后两次检查耳机路由。
    func start(preferences: Preferences, remaining: TimeInterval) throws {
        stop()
        guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
        do {
            try activateHeadphones()
            let sleepPlayer = try player(named: preferences.sleepSound.rawValue)
            let alarmPlayer = try player(named: preferences.alarmSound.rawValue)
            sleepPlayer.numberOfLoops = -1
            sleepPlayer.volume = preferences.sleepVolume
            alarmPlayer.numberOfLoops = 2
            alarmPlayer.volume = preferences.alarmVolume
            ambience = sleepPlayer
            alarm = alarmPlayer
            active = true
            guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
            if remaining > 0 {
                guard sleepPlayer.play(), alarmPlayer.play(atTime: alarmPlayer.deviceCurrentTime + remaining) else { throw AudioFailure.playbackFailed }
            } else {
                guard alarmPlayer.play() else { throw AudioFailure.playbackFailed }
            }
        } catch {
            stop()
            throw error
        }
    }

    /// 试听沿用同一耳机门禁和断连保护，任何启动错误均停止音频。
    func preview(name: String, volume: Float) throws {
        stop()
        do {
            try activateHeadphones()
            let preview = try player(named: name)
            preview.volume = min(1, max(0.05, volume))
            ambience = preview
            active = true
            guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
            guard preview.play() else { throw AudioFailure.playbackFailed }
        } catch {
            stop()
            throw error
        }
    }

    /// 激活前后均核验输出，并请求系统在耳机断开时中断会话。
    private func activateHeadphones() throws {
        guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPrefersInterruptionOnRouteDisconnect(true)
        try session.setActive(true)
        guard isHeadphoneConnected else { throw AudioFailure.noHeadphones }
    }

    /// 提醒开始后停止助眠音，避免两条音轨叠加。
    func stopAmbienceIfRinging() { ambience?.stop() }

    /// 在停止后清除预约及锁屏信息，不留下可外放的通知声音。
    func stop() {
        active = false
        ambience?.stop()
        alarm?.stop()
        ambience = nil
        alarm = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 提供锁屏可见的到点时间及暂停入口。
    func updateNowPlaying(deadline: Date, duration: TimeInterval) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "耳憩 · 仅耳机提醒",
            MPMediaItemPropertyArtist: "\(deadline.formatted(date: .omitted, time: .shortened)) 轻轻唤醒",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, duration - deadline.timeIntervalSinceNow),
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
    }

    /// 从应用内读取原创合成音频，不需要网络或麦克风权限。
    private func player(named name: String) throws -> AVAudioPlayer {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { throw AudioFailure.missingResource }
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }

    /// 输出变化时立即关闭非耳机播放；重连仅刷新状态，不自动响铃。
    private func routeChanged() {
        if active && !isHeadphoneConnected { safetyStop("耳机已断开，声音已停止。重新连接后请手动继续。") }
        onRouteUpdate?()
    }

    /// 统一执行安全停止，并通知会话层标记中断。
    private func safetyStop(_ reason: String) {
        guard active else { onRouteUpdate?(); return }
        stop()
        onSafetyStop?(reason)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
    }
}

#if DEBUG
@MainActor
final class PreviewAudio: RestAudio {
    var isHeadphoneConnected = true
    var routeName: String { isHeadphoneConnected ? "测试耳机（无声模拟）" : "尚未连接耳机" }
    var onSafetyStop: ((String) -> Void)?
    var onRouteUpdate: (() -> Void)?
    var onPause: (() -> Void)?
    var starts = 0
    var previews = 0
    var stops = 0
    var failure: Error?

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
    }
    /// 记录停止次数以验证断连和暂停的行为。
    func stop() { stops += 1 }
    /// 测试环境不占用系统锁屏。
    func updateNowPlaying(deadline: Date, duration: TimeInterval) {}
    /// 注入断连事件，验证会话立即阻止播放。
    func disconnect() {
        isHeadphoneConnected = false
        onSafetyStop?("耳机已断开，声音已停止。重新连接后请手动继续。")
        onRouteUpdate?()
    }
    /// 注入重连事件，验证不会隐式恢复。
    func reconnect() { isHeadphoneConnected = true; onRouteUpdate?() }
}
#endif
