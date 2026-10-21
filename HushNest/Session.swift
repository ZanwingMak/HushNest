import Foundation

enum SleepSound: String, Codable, CaseIterable, Identifiable {
    case none, rain, ocean, brown, pink, stream, forest, fireplace, night, custom
    var id: String { rawValue }
    var title: String { switch self {
    case .custom: L("自定义声音"); case .none: L("不播放助眠音"); case .rain: L("细雨"); case .ocean: L("潮汐"); case .brown: L("棕噪音")
    case .pink: L("粉红噪音"); case .stream: L("溪流"); case .forest: L("林间"); case .fireplace: L("炉火"); case .night: L("夏夜")
    } }
    var symbol: String { switch self {
    case .custom: "music.note"; case .none: "speaker.slash"; case .rain: "cloud.rain"; case .ocean: "water.waves"; case .brown, .pink: "waveform"
    case .stream: "drop"; case .forest: "tree"; case .fireplace: "flame"; case .night: "moon.stars"
    } }
    var subtitle: String { switch self {
    case .custom: L("仅保存在本机的音轨"); case .none: L("安静休息 · 后台仅有无声通知"); case .rain: L("温润雨幕，柔化高频"); case .ocean: L("缓慢起落的海浪")
    case .brown: L("深沉平稳，减轻沙沙声"); case .pink: L("均衡柔和的声音毯"); case .stream: L("细水流淌，轻盈起伏")
    case .forest: L("风过树梢，远处鸟鸣"); case .fireplace: L("温暖炉火，轻微噼啪"); case .night: L("远处虫鸣，宁静夜色")
    } }
}

enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case dawn, bell, orbit, piano, marimba, harp, bamboo, aurora, classic, twinbell, digital, pulse, beacon, reveille, custom
    var id: String { rawValue }
    var title: String { switch self {
    case .custom: L("自定义声音"); case .classic: L("经典滴滴"); case .twinbell: L("机械双铃"); case .digital: L("数字闹钟")
    case .pulse: L("急促脉冲"); case .beacon: L("交替信号"); case .reveille: L("起床号角")
    case .dawn: L("晨光"); case .bell: L("风铃"); case .orbit: L("星轨"); case .piano: L("柔钢琴")
    case .marimba: L("木琴"); case .harp: L("竖琴"); case .bamboo: L("竹语"); case .aurora: L("极光")
    } }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case forest, ocean, dusk, rose
    var id: String { rawValue }
    var title: String { switch self { case .forest: L("松林"); case .ocean: L("海湾"); case .dusk: L("暮紫"); case .rose: L("玫瑰") } }
}

struct Preferences: Codable, Equatable {
    var minutes = 30
    var seconds = 0
    var vibrationEnabled = false
    var repeatAlarm = false
    var precisePresets: [Int] = []
    var customSleepID: UUID?
    var customAlarmID: UUID?
    var sleepSound: SleepSound = .rain
    var alarmSound: AlarmSound = .dawn
    var sleepVolume: Float = 0.18
    var alarmVolume: Float = 0.55
    var snoozeMinutes = 5
    var presets = [15, 30, 45, 60]

    var durationSeconds: TimeInterval { TimeInterval(minutes * 60 + seconds) }
    var presetDurations: [Int] { Array(Set(presets.map { $0 * 60 } + precisePresets)).sorted() }

    private enum CodingKeys: String, CodingKey {
        case repeatAlarm, customSleepID, customAlarmID, minutes, seconds, vibrationEnabled, precisePresets, sleepSound, alarmSound, sleepVolume, alarmVolume, snoozeMinutes, presets
    }

    /// 新安装使用统一默认值。
    init() {}

    /// 为新增秒数和震动提供迁移默认值，保留旧版本的声音、时长与预设。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        customSleepID = try values.decodeIfPresent(UUID.self, forKey: .customSleepID)
        customAlarmID = try values.decodeIfPresent(UUID.self, forKey: .customAlarmID)
        minutes = try values.decodeIfPresent(Int.self, forKey: .minutes) ?? 30
        seconds = try values.decodeIfPresent(Int.self, forKey: .seconds) ?? 0
        repeatAlarm = try values.decodeIfPresent(Bool.self, forKey: .repeatAlarm) ?? false
        vibrationEnabled = try values.decodeIfPresent(Bool.self, forKey: .vibrationEnabled) ?? false
        precisePresets = try values.decodeIfPresent([Int].self, forKey: .precisePresets) ?? []
        sleepSound = try values.decodeIfPresent(SleepSound.self, forKey: .sleepSound) ?? .rain
        alarmSound = try values.decodeIfPresent(AlarmSound.self, forKey: .alarmSound) ?? .dawn
        sleepVolume = try values.decodeIfPresent(Float.self, forKey: .sleepVolume) ?? 0.18
        alarmVolume = try values.decodeIfPresent(Float.self, forKey: .alarmVolume) ?? 0.55
        snoozeMinutes = try values.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
        presets = try values.decodeIfPresent([Int].self, forKey: .presets) ?? [15, 30, 45, 60]
    }

    /// 限制持久化或迁移后的数据，避免无效音量、时长和预设。
    mutating func normalize() {
        minutes = min(720, max(0, minutes))
        seconds = min(59, max(0, seconds))
        if minutes == 720 { seconds = 0 }
        if minutes == 0 && seconds == 0 { seconds = 1 }
        precisePresets = Array(Set(precisePresets.filter { (1...43200).contains($0) && $0 % 60 != 0 })).sorted()
        sleepVolume = sleepVolume.isFinite ? min(0.6, max(0.01, sleepVolume)) : 0.18
        alarmVolume = alarmVolume.isFinite ? min(1, max(0.05, alarmVolume)) : 0.55
        snoozeMinutes = min(30, max(1, snoozeMinutes))
        presets = Array(Set(presets.filter { (1...720).contains($0) })).sorted()
    }
}

enum SessionPhase: String, Codable {
    case resting, paused, ringing, blocked
}

struct RestSession: Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var deadline: Date
    var duration: TimeInterval
    var phase: SessionPhase
    var pausedRemaining: TimeInterval?
    var snoozeCount = 0
    var reason: String?
    var accumulatedRest: TimeInterval = 0
    var restingSince: Date?

    /// 创建使用绝对截止时间的会话，锁屏和页面切换不改变计时。
    init(now: Date, duration: TimeInterval) {
        self.id = UUID()
        self.startedAt = now
        self.duration = max(1, duration)
        self.deadline = now.addingTimeInterval(max(1, duration))
        self.phase = .resting
        self.restingSince = now
    }

    /// 返回暂停时固定或运行时实时计算的剩余秒数。
    func remaining(at now: Date) -> TimeInterval {
        max(0, pausedRemaining ?? deadline.timeIntervalSince(now))
    }

    /// 根据截止时间进入响铃；持续响铃模式仅由用户或安全事件停止。
    mutating func tick(at now: Date, repeatAlarm: Bool = false) -> Bool {
        if phase == .resting && now >= deadline {
            settleRest(at: now)
            phase = .ringing
        }
        return phase == .ringing && !repeatAlarm && now.timeIntervalSince(deadline) >= 180
    }

    /// 手动暂停冻结剩余时间；中断暂停保留原截止时间，避免误报仍在运行。
    mutating func pause(at now: Date, reason: String? = nil) {
        guard phase == .resting || phase == .ringing else { return }
        settleRest(at: now)
        if reason == nil { pausedRemaining = remaining(at: now) }
        phase = reason == nil ? .paused : .blocked
        self.reason = reason
    }

    /// 恢复暂停会话，已到期时重新建立完整的响铃窗口。
    mutating func resume(at now: Date) {
        guard phase == .paused || phase == .blocked else { return }
        if let pausedRemaining { deadline = now.addingTimeInterval(pausedRemaining) }
        pausedRemaining = nil
        reason = nil
        if now >= deadline {
            deadline = now
            phase = .ringing
        } else {
            phase = .resting
            restingSince = now
        }
    }

    /// 将响铃会话延后指定时长，并重置本轮进度。
    mutating func snooze(at now: Date, minutes: Int) {
        guard phase == .ringing else { return }
        duration = TimeInterval(max(1, minutes) * 60)
        deadline = now.addingTimeInterval(duration)
        pausedRemaining = nil
        phase = .resting
        restingSince = now
        snoozeCount += 1
    }

    /// 统计真正运行的休息时长，不把暂停、断连和等待操作的时间计入记录。
    func restedSeconds(at now: Date) -> TimeInterval {
        accumulatedRest + (restingSince.map { max(0, min(now, deadline).timeIntervalSince($0)) } ?? 0)
    }

    /// 在离开运行状态时结算本段休息，防止多次暂停重复累计。
    private mutating func settleRest(at now: Date) {
        accumulatedRest = restedSeconds(at: now)
        restingSince = nil
    }
}

struct RestRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let minutes: Int
    let completed: Bool
    let sound: SleepSound
    var seconds: Int? = nil
}

enum Schedule {
    /// 计算下一次本地钟表时间，跨午夜和夏令时均使用日历规则。
    static func nextOccurrence(hour: Int, minute: Int, after now: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
    }
}
