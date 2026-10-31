import XCTest
import AVFoundation
import UIKit
import SwiftUI
import CryptoKit
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

    /// 持续模式超过三分钟和多轮音轨时仍保持响铃，稍后提醒可重新计时。
    func testRepeatingAlarmHasNoAutomaticTimeout() {
        var session = RestSession(now: start, duration: 1)
        XCTAssertFalse(session.tick(at: start.addingTimeInterval(3601), repeatAlarm: true))
        XCTAssertEqual(session.phase, .ringing)
        session.snooze(at: start.addingTimeInterval(3601), minutes: 5)
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(3601)), 300)
    }

    /// 从旧配置迁移时保留限时模式，新选择可以持久化。
    func testRepeatAlarmPreferenceMigration() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(old.repeatAlarm)
        var settings = old
        settings.repeatAlarm = true
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings)).repeatAlarm)
    }

    /// 不播放音频，直接确认真实播放器使用无限循环且限时模式保持三轮。
    @MainActor func testAlarmPlayerLoopPolicyWithoutPlayback() throws {
        let audio = HeadphoneAudio()
        defer { audio.stop() }
        var settings = Preferences()
        XCTAssertEqual(try audio.prepareAlarm(preferences: settings).numberOfLoops, 2)
        settings.repeatAlarm = true
        let player = try audio.prepareAlarm(preferences: settings)
        XCTAssertEqual(player.numberOfLoops, -1)
        XCTAssertFalse(player.isPlaying)
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
        XCTAssertEqual(settings.minutes, 0)
        XCTAssertEqual(settings.seconds, 1)
        XCTAssertEqual(settings.sleepVolume, 0.18)
        XCTAssertEqual(settings.alarmVolume, 1)
        XCTAssertEqual(settings.snoozeMinutes, 1)
        XCTAssertEqual(settings.presets, [10])
    }

    /// 新增字段兼容旧配置，同时允许最低 1% 助眠音量与秒级计时。
    func testPrecisePreferencesAndLegacyMigration() throws {
        let legacy = Data("{\"minutes\":25,\"sleepSound\":\"ocean\",\"sleepVolume\":0.12,\"presets\":[15,25,45,90]}".utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(decoded.minutes, 25)
        XCTAssertEqual(decoded.sleepSound, .ocean)
        XCTAssertFalse(decoded.vibrationEnabled)
        var settings = Preferences()
        settings.minutes = 0
        settings.seconds = 15
        settings.sleepVolume = 0
        settings.normalize()
        XCTAssertEqual(settings.durationSeconds, 15)
        XCTAssertEqual(settings.sleepVolume, 0.01)
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
        let names = SleepSound.allCases.filter { $0 != .none && $0 != .custom }.map(\.rawValue)
            + AlarmSound.allCases.filter { $0 != .custom }.map(\.rawValue)
        for name in names {
            let url = try XCTUnwrap(HeadphoneAudio.bundledURL(named: name))
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 200_000)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 22050))
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            XCTAssertGreaterThan((0..<Int(buffer.frameLength)).map { abs(samples[$0]) }.max() ?? 0, 0.0001)
        }
    }

    /// 实录资源必须匹配已核实的来源、许可及摘要，防止重新生成时被同名合成噪音覆盖。
    func testFieldRecordingsMatchLicensedCatalog() throws {
        let catalogURL = try XCTUnwrap(Bundle.main.url(forResource: "FieldRecordings", withExtension: "json"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let recordings = try XCTUnwrap(catalog["recordings"] as? [[String: Any]])
        XCTAssertEqual(Set(recordings.compactMap { $0["id"] as? String }), Set(["rain", "ocean", "stream", "forest", "fireplace", "night"]))
        var hashes = Set<String>()
        for recording in recordings {
            let name = try XCTUnwrap(recording["id"] as? String)
            XCTAssertTrue(["CC0-1.0", "Public Domain"].contains(recording["license"] as? String ?? ""))
            XCTAssertFalse((recording["author"] as? String ?? "").isEmpty)
            XCTAssertTrue((recording["source"] as? String ?? "").hasPrefix("https://"))
            let url = try XCTUnwrap(HeadphoneAudio.bundledURL(named: name))
            let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, recording["outputSHA256"] as? String, name)
            hashes.insert(hash)
            let audio = try AVAudioFile(forReading: url)
            XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate,
                           try XCTUnwrap(recording["seconds"] as? Double), accuracy: 0.01)
            XCTAssertEqual(audio.processingFormat.sampleRate, 44100)
            XCTAssertEqual(audio.processingFormat.channelCount, 2)
            XCTAssertGreaterThanOrEqual(recording["sourceSeconds"] as? Double ?? 0,
                                       (recording["start"] as? Double ?? 0) + (recording["seconds"] as? Double ?? 0) + (recording["crossfade"] as? Double ?? 0))
        }
        XCTAssertEqual(hashes.count, 6)
    }

    /// 解码实际循环首尾，确认没有静音接缝或大于相邻采样变化的突跳；不创建播放会话。
    func testSleepTrackLoopBoundariesAreContinuous() throws {
        for name in ["rain", "ocean", "stream", "forest", "fireplace", "night", "brown", "pink"] {
            let url = try XCTUnwrap(HeadphoneAudio.bundledURL(named: name))
            let audio = try AVAudioFile(forReading: url)
            let first = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 2048))
            let last = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 2048))
            try audio.read(into: first)
            audio.framePosition = audio.length - 2048
            try audio.read(into: last)
            for channel in 0..<Int(audio.processingFormat.channelCount) {
                let head = try XCTUnwrap(first.floatChannelData?[channel])
                let tail = try XCTUnwrap(last.floatChannelData?[channel])
                let energy = (0..<2048).reduce(Float(0)) { $0 + head[$1] * head[$1] + tail[$1] * tail[$1] }
                XCTAssertGreaterThan(energy, 0.01, name)
                let stepEnergy = (1..<2048).reduce(Float(0)) { value, index in
                    let headStep = head[index] - head[index - 1]
                    let tailStep = tail[index] - tail[index - 1]
                    return value + headStep * headStep + tailStep * tailStep
                }
                XCTAssertLessThanOrEqual(abs(head[0] - tail[2047]), max(0.01, 5 * sqrt(stepEnergy / 4094)), "\(name) channel \(channel)")
            }
        }
    }

    /// 用真实 Apple 文件解码器及播放器核对八条长助眠音，读取头尾确认无编码补零，全程不播放。
    @MainActor func testSleepTracksHaveLongGaplessDurations() throws {
        let audio = HeadphoneAudio()
        for sound in SleepSound.allCases where sound != .none && sound != .custom {
            let url = try XCTUnwrap(HeadphoneAudio.bundledURL(named: sound.rawValue))
            XCTAssertEqual(url.pathExtension, "m4a")
            let file = try AVAudioFile(forReading: url)
            let player = try audio.preparePreview(name: sound.rawValue, volume: 0.1)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            XCTAssertGreaterThanOrEqual(seconds, 300, sound.rawValue)
            XCTAssertEqual(player.duration, seconds, accuracy: 1 / file.processingFormat.sampleRate, sound.rawValue)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4410))
            for position in [AVAudioFramePosition(0), file.length - 4410] {
                file.framePosition = position
                try file.read(into: buffer)
                XCTAssertEqual(buffer.frameLength, 4410, sound.rawValue)
                let samples = try XCTUnwrap(buffer.floatChannelData?[0])
                let energy = (0..<4410).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
                XCTAssertGreaterThan(energy, 0.001, sound.rawValue)
            }
        }
        audio.stop()
    }

    /// 比较真实文件中相隔旧循环周期的波形，防止把短片段复制成表面上更长的文件。
    func testSleepTracksDoNotRepeatTheirFormerShortExcerpt() throws {
        let formerPeriods: [String: Double] = ["rain": 55, "ocean": 85, "stream": 65, "forest": 70,
                                             "fireplace": 22, "night": 44, "brown": 30, "pink": 30]
        for (name, period) in formerPeriods {
            let file = try AVAudioFile(forReading: XCTUnwrap(HeadphoneAudio.bundledURL(named: name)))
            let first = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100))
            let later = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100))
            file.framePosition = 44100
            try file.read(into: first)
            file.framePosition = AVAudioFramePosition((period + 1) * file.processingFormat.sampleRate)
            try file.read(into: later)
            let a = try XCTUnwrap(first.floatChannelData?[0])
            let b = try XCTUnwrap(later.floatChannelData?[0])
            let dot = (0..<44100).reduce(Double(0)) { $0 + Double(a[$1]) * Double(b[$1]) }
            let aEnergy = (0..<44100).reduce(Double(0)) { $0 + Double(a[$1]) * Double(a[$1]) }
            let bEnergy = (0..<44100).reduce(Double(0)) { $0 + Double(b[$1]) * Double(b[$1]) }
            XCTAssertLessThan(abs(dot / sqrt(max(1e-20, aEnergy * bEnergy))), 0.95, name)
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

    /// 所有主题在浅色和深色外观下都维持主按钮文字对比度。
    @MainActor func testEveryThemeMeetsButtonContrast() throws {
        for theme in AppTheme.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                let foreground = try XCTUnwrap(UIColor(named: "OnAccent")).resolvedColor(with: traits)
                let background = UIColor(theme.accent).resolvedColor(with: traits)
                let a = luminance(foreground), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, theme.rawValue)
            }
        }
    }

    /// 检查打包后的图标具有实际颜色内容，防止再次发布全黑图标。
    @MainActor func testCompiledAppIconContainsArtwork() throws {
        let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []
        let iconURL = try XCTUnwrap(urls.first { $0.lastPathComponent.hasPrefix("AppIcon") })
        let image = try XCTUnwrap(UIImage(contentsOfFile: iconURL.path)?.cgImage)
        let bytes = try XCTUnwrap(image.dataProvider?.data)
        let data = CFDataGetBytePtr(bytes)!
        let count = CFDataGetLength(bytes)
        let distinct = Set(stride(from: 0, to: count, by: 4).map { data[$0] })
        XCTAssertGreaterThan(distinct.count, 10)
    }

    /// 操作真实 AVAudioPlayer 的增益，确认试听音量即时改变且不重置进度，不启动播放。
    @MainActor func testLivePreviewGainChangesActualPlayer() throws {
        let audio = HeadphoneAudio()
        let player = try audio.preparePreview(name: "classic", volume: 0.55)
        player.currentTime = 4
        audio.updatePreviewVolume(0.1)
        XCTAssertEqual(player.volume, 0.1, accuracy: 0.001)
        XCTAssertEqual(player.currentTime, 4, accuracy: 0.1)
        audio.updatePreviewVolume(0.9)
        XCTAssertEqual(player.volume, 0.9, accuracy: 0.001)
        XCTAssertFalse(player.isPlaying)
        audio.stop()
    }

    /// 六种语言资源完整覆盖相同文案，并保留动态占位符。
    func testLocalizationsHaveMatchingKeysAndPlaceholders() throws {
        var baseline: [String: String] = [:]
        for language in ["zh-Hans", "zh-Hant", "en", "ja", "ko", "es"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            let values = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            if baseline.isEmpty { baseline = values }
            XCTAssertEqual(Set(values.keys), Set(baseline.keys))
            for (key, value) in values {
                XCTAssertEqual(key.components(separatedBy: "%@").count, value.components(separatedBy: "%@").count, key)
            }
            if language == "en" { XCTAssertEqual(values["休息"], "Rest") }
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
