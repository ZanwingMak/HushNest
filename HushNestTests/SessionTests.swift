import XCTest
import AVFoundation
import UIKit
@testable import HushNest

final class SessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// 验证绝对截止时间不依赖定时器回调次数。
    func testDeadlineCatchesUpAfterDelayedTick() {
        var session = RestSession(now: start, duration: 60)
        XCTAssertFalse(session.tick(at: start.addingTimeInterval(90)))
        XCTAssertEqual(session.phase, .ringing)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(90)), 0)
    }

    /// 验证暂停冻结剩余时间并在恢复后重建截止时间。
    func testManualPauseFreezesTime() {
        var session = RestSession(now: start, duration: 60)
        session.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(session.phase, .paused)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(200)), 40)
        session.resume(at: start.addingTimeInterval(200))
        XCTAssertEqual(session.deadline, start.addingTimeInterval(240))
    }

    /// 验证断连中断保留原截止时间，且不会自己变为响铃。
    func testBlockedSessionDoesNotRingWithoutExplicitResume() {
        var session = RestSession(now: start, duration: 60)
        session.pause(at: start.addingTimeInterval(20), reason: "断连")
        XCTAssertFalse(session.tick(at: start.addingTimeInterval(100)))
        XCTAssertEqual(session.phase, .blocked)
        XCTAssertEqual(session.deadline, start.addingTimeInterval(60))
        session.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(session.phase, .ringing)
    }

    /// 验证仅响铃阶段可以稍后提醒，并重新建立完整倒计时。
    func testSnoozeOnlyFromRinging() {
        var session = RestSession(now: start, duration: 60)
        session.snooze(at: start, minutes: 5)
        XCTAssertEqual(session.snoozeCount, 0)
        _ = session.tick(at: start.addingTimeInterval(60))
        session.snooze(at: start.addingTimeInterval(61), minutes: 5)
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.snoozeCount, 1)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(61)), 300)
    }

    /// 验证无人操作时响铃在三分钟后自动结束。
    func testAlarmTimeout() {
        var session = RestSession(now: start, duration: 60)
        XCTAssertFalse(session.tick(at: start.addingTimeInterval(239)))
        XCTAssertTrue(session.tick(at: start.addingTimeInterval(240)))
    }

    /// 验证跨午夜预约使用下一天的本地时间。
    func testClockScheduleAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23, minute: 50))!
        let next = Schedule.nextOccurrence(hour: 0, minute: 10, after: now, calendar: calendar)
        XCTAssertEqual(next.timeIntervalSince(now), 1200)
    }

    /// 验证不存在的夏令时钟点按系统日历推进到下一有效时间。
    func testClockScheduleHandlesDSTGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 50))!
        let next = Schedule.nextOccurrence(hour: 2, minute: 30, after: now, calendar: calendar)
        XCTAssertGreaterThan(next, now)
        XCTAssertEqual(calendar.component(.hour, from: next), 3)
    }

    /// 验证数据损坏或越界不会产生零音量和非法时长。
    func testPreferenceNormalization() {
        var settings = Preferences()
        settings.minutes = -1
        settings.sleepVolume = .nan
        settings.alarmVolume = 2
        settings.snoozeMinutes = 0
        settings.presets = [0, 10, 10, 900]
        settings.normalize()
        XCTAssertEqual(settings.minutes, 1)
        XCTAssertEqual(settings.sleepVolume, 0.18)
        XCTAssertEqual(settings.alarmVolume, 1)
        XCTAssertEqual(settings.snoozeMinutes, 1)
        XCTAssertEqual(settings.presets, [10])
    }

    /// 验证路由白名单拒绝空路由、扬声器、车载、AirPlay 和混合输出。
    @MainActor func testRouteGateRejectsUnsafeOutputs() {
        XCTAssertFalse(HeadphoneAudio.allOutputsArePrivate([]))
        for port: AVAudioSession.Port in [.builtInSpeaker, .builtInReceiver, .airPlay, .carAudio, .HDMI, .usbAudio] {
            XCTAssertFalse(HeadphoneAudio.allOutputsArePrivate([port]))
            XCTAssertFalse(HeadphoneAudio.allOutputsArePrivate([.headphones, port]))
        }
        XCTAssertTrue(HeadphoneAudio.allOutputsArePrivate([.headphones]))
        XCTAssertTrue(HeadphoneAudio.allOutputsArePrivate([.bluetoothA2DP]))
    }

    /// 验证每条正式音频资源可解码，且具有非零时长和可听数据。
    @MainActor func testAllBundledAudioDecodes() throws {
        for name in SleepSound.allCases.map(\.rawValue) + AlarmSound.allCases.map(\.rawValue) {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "wav"))
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 200_000)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 22050))
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            XCTAssertGreaterThan((0..<Int(buffer.frameLength)).map { abs(samples[$0]) }.max() ?? 0, 0.0001)
        }
    }

    /// 使用真实音频实现确认模拟器扬声器路由不能启动提醒或试听。
    @MainActor func testRealAudioRejectsSimulatorSpeaker() throws {
        #if targetEnvironment(simulator)
        let audio = HeadphoneAudio()
        XCTAssertFalse(audio.isHeadphoneConnected)
        XCTAssertThrowsError(try audio.start(preferences: Preferences(), remaining: 1))
        XCTAssertThrowsError(try audio.preview(name: "rain", volume: 0.2))
        audio.stop()
        #endif
    }

    /// 超过原截止时间后主动恢复，应给出完整三分钟提醒窗口。
    func testOverdueResumeGetsFreshRingWindow() {
        var session = RestSession(now: start, duration: 60)
        session.pause(at: start.addingTimeInterval(10), reason: "断连")
        let resumedAt = start.addingTimeInterval(3600)
        session.resume(at: resumedAt)
        XCTAssertEqual(session.phase, .ringing)
        XCTAssertFalse(session.tick(at: resumedAt))
        XCTAssertTrue(session.tick(at: resumedAt.addingTimeInterval(180)))
    }

    /// 检查按钮前景色实际不透明，浅深主题的前景和背景均满足文字对比度。
    @MainActor func testPrimaryButtonColorContrast() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let foreground = try XCTUnwrap(UIColor(named: "OnAccent")).resolvedColor(with: traits)
            let background = try XCTUnwrap(UIColor(named: "AccentColor")).resolvedColor(with: traits)
            var alpha: CGFloat = 0
            foreground.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1, accuracy: 0.001)
            let a = luminance(foreground)
            let b = luminance(background)
            XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
        }
    }

    /// 将 sRGB 色彩转换为相对亮度，用于验证可读性而非仅比对配置文本。
    private func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let channels = [r, g, b].map { value in
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}
