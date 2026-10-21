import Foundation

enum SleepSound: String, Codable, CaseIterable, Identifiable {
    case rain, ocean, brown
    var id: String { rawValue }
    var title: String { switch self { case .rain: "细雨"; case .ocean: "潮汐"; case .brown: "棕噪音" } }
    var symbol: String { switch self { case .rain: "cloud.rain"; case .ocean: "water.waves"; case .brown: "waveform" } }
    var subtitle: String { switch self { case .rain: "把喧嚣留在窗外"; case .ocean: "随着海浪慢慢放松"; case .brown: "柔和、低沉的陪伴" } }
}

enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case dawn, bell, orbit
    var id: String { rawValue }
    var title: String { switch self { case .dawn: "晨光"; case .bell: "风铃"; case .orbit: "星轨" } }
}

struct Preferences: Codable, Equatable {
    var minutes = 25
    var sleepSound: SleepSound = .rain
    var alarmSound: AlarmSound = .dawn
    var sleepVolume: Float = 0.18
    var alarmVolume: Float = 0.55
    var snoozeMinutes = 5
    var presets = [15, 25, 45, 90]

    /// 限制持久化或迁移后的数据，避免无效音量、时长和预设。
    mutating func normalize() {
        minutes = min(720, max(1, minutes))
        sleepVolume = sleepVolume.isFinite ? min(0.6, max(0.05, sleepVolume)) : 0.18
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

    /// 根据绝对时间切换到响铃状态，并在三分钟后返回自动结束信号。
    mutating func tick(at now: Date) -> Bool {
        if phase == .resting && now >= deadline {
            settleRest(at: now)
            phase = .ringing
        }
        return phase == .ringing && now.timeIntervalSince(deadline) >= 180
    }

    /// 手动暂停冻结剩余时间；中断暂停保留原截止时间，避免误报仍在运行。
    mutating func pause(at now: Date, reason: String? = nil) {
        guard phase == .resting || phase == .ringing else { return }
        settleRest(at: now)
        if reason == nil { pausedRemaining = remaining(at: now) }
        phase = reason == nil ? .paused : .blocked
        self.reason = reason
    }

    /// 仅在用户明确恢复后继续，已到期的中断会话直接进入响铃。
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
}

enum Schedule {
    /// 计算下一次本地钟表时间，跨午夜和夏令时均使用日历规则。
    static func nextOccurrence(hour: Int, minute: Int, after now: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
    }
}
