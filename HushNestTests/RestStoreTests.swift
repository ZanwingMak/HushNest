import XCTest
@testable import HushNest

@MainActor
final class RestStoreTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var defaults: UserDefaults!
    private var audio: PreviewAudio!
    private var store: RestStore!

    /// 每个用例使用独立本地数据、可控时钟和完全无声的音频替身。
    override func setUp() async throws {
        let suite = "HushNest.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        audio = PreviewAudio()
        store = RestStore(audio: audio, defaults: defaults, clock: { [unowned self] in self.now }, runsTimer: false, notificationsEnabled: false)
    }

    /// 无耳机时不得创建会话或触发音频。
    func testCannotStartWithoutHeadphones() {
        audio.isHeadphoneConnected = false
        store.start()
        XCTAssertNil(store.session)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(audio.starts, 0)
    }

    /// 启动失败必须保留空闲状态，不能出现虚假的运行中倒计时。
    func testAudioFailureIsAtomic() {
        audio.failure = AudioFailure.playbackFailed
        store.start()
        XCTAssertNil(store.session)
        XCTAssertNotNil(store.errorMessage)
    }

    /// 拒绝无效时长，避免 Date 和硬件调度的非法参数。
    func testRejectsInvalidDurations() {
        for duration in [Double.nan, .infinity, -1, 0, 86401] {
            store.start(duration: duration)
            XCTAssertNil(store.session)
        }
        XCTAssertEqual(audio.starts, 0)
    }

    /// 重复点击开始只能创建一个会话和一个音频预约。
    func testRepeatedStartDoesNotDuplicate() {
        store.start(duration: 60)
        let id = store.session?.id
        store.start(duration: 120)
        XCTAssertEqual(store.session?.id, id)
        XCTAssertEqual(audio.starts, 1)
    }

    /// 断连立即停止，重连不自动播放，只有手动恢复才启动。
    func testDisconnectReconnectRequiresExplicitResume() {
        store.start(duration: 60)
        audio.disconnect()
        XCTAssertEqual(store.session?.phase, .blocked)
        XCTAssertGreaterThan(audio.stops, 0)
        audio.reconnect()
        XCTAssertEqual(audio.starts, 1)
        XCTAssertEqual(store.session?.phase, .blocked)
        store.resume()
        XCTAssertEqual(audio.starts, 2)
        XCTAssertEqual(store.session?.phase, .resting)
    }

    /// 无耳机恢复失败时保留中断，不恢复预约或倒计时状态。
    func testResumeWithoutHeadphonesStaysBlocked() {
        store.start(duration: 60)
        audio.disconnect()
        store.resume()
        XCTAssertEqual(store.session?.phase, .blocked)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(audio.starts, 1)
    }

    /// 手动暂停撤销提醒，经过原截止时间仍保持暂停。
    func testPauseCancelsDeadlineUntilResume() {
        store.start(duration: 60)
        now.addTimeInterval(10)
        store.pause()
        now.addTimeInterval(100)
        store.tick()
        XCTAssertEqual(store.session?.phase, .paused)
        XCTAssertEqual(store.remaining, 50)
        store.resume()
        XCTAssertEqual(store.session?.deadline, now.addingTimeInterval(50))
    }

    /// 响铃、稍后提醒、完成及统计可贯通，结束操作保持幂等。
    func testCompleteLifecycleWithSnooze() {
        store.start(duration: 60)
        now.addTimeInterval(60)
        store.tick()
        XCTAssertEqual(store.session?.phase, .ringing)
        store.snooze()
        XCTAssertEqual(store.remaining, 300)
        XCTAssertEqual(store.session?.snoozeCount, 1)
        now.addTimeInterval(300)
        store.tick()
        store.finish(completed: true)
        store.finish(completed: true)
        XCTAssertNil(store.session)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.completedCount, 1)
    }

    /// 应用重启只恢复中断快照，绝不静默重启音频。
    func testRelaunchRestoresBlockedSnapshot() {
        store.start(duration: 60)
        let restoredAudio = PreviewAudio()
        let restored = RestStore(audio: restoredAudio, defaults: defaults, clock: { [unowned self] in self.now }, runsTimer: false, notificationsEnabled: false)
        XCTAssertEqual(restored.session?.phase, .blocked)
        XCTAssertEqual(restoredAudio.starts, 0)
        XCTAssertEqual(restored.session?.id, store.session?.id)
    }

    /// 正常结束后清除恢复快照，并持久保存历史。
    func testFinishedSessionDoesNotRestore() {
        store.start(duration: 60)
        store.finish(completed: false)
        let restored = RestStore(audio: PreviewAudio(), defaults: defaults, runsTimer: false, notificationsEnabled: false)
        XCTAssertNil(restored.session)
        XCTAssertEqual(restored.records.count, 1)
        XCTAssertEqual(restored.completedCount, 0)
    }

    /// 常用预设支持添加删除与去重，配置保存后可重新读取。
    func testPresetAndSettingsPersistence() {
        store.addPreset(37)
        store.addPreset(37)
        store.addPreset(-1)
        store.preferences.sleepSound = .ocean
        store.preferences.minutes = 37
        store.removePreset(15)
        let restored = RestStore(audio: PreviewAudio(), defaults: defaults, runsTimer: false, notificationsEnabled: false)
        XCTAssertEqual(restored.preferences.presets.filter { $0 == 37 }.count, 1)
        XCTAssertFalse(restored.preferences.presets.contains(15))
        XCTAssertEqual(restored.preferences.sleepSound, .ocean)
        XCTAssertEqual(restored.preferences.minutes, 37)
    }

    /// 响铃超时自动结束，同时清理音频并写入完成记录。
    func testRingingTimeoutStopsAudio() {
        store.start(duration: 1)
        now.addTimeInterval(181)
        store.tick()
        XCTAssertNil(store.session)
        XCTAssertEqual(store.completedCount, 1)
        XCTAssertGreaterThan(audio.stops, 0)
    }

    /// 清空记录保持当前会话，不影响计时。
    func testClearHistoryDoesNotStopCurrentSession() {
        store.start(duration: 60)
        store.finish(completed: false)
        store.start(duration: 120)
        store.clearHistory()
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(store.session?.phase, .resting)
    }

    /// 试听必须通过耳机门禁，且不能创建会话或历史记录。
    func testPreviewIsPrivateAndIndependentOfTimer() throws {
        audio.isHeadphoneConnected = false
        XCTAssertThrowsError(try store.preview(name: "rain", volume: 0.2))
        XCTAssertNil(store.previewing)
        audio.isHeadphoneConnected = true
        try store.preview(name: "rain", volume: 0.2)
        XCTAssertEqual(store.previewing, "rain")
        XCTAssertNil(store.session)
        XCTAssertEqual(audio.previews, 1)
        try store.preview(name: "rain", volume: 0.2)
        XCTAssertNil(store.previewing)
    }

    /// 启动休息会停止试听，避免同时存在两种播放任务。
    func testStartingSessionStopsPreview() throws {
        try store.preview(name: "rain", volume: 0.2)
        store.start(duration: 60)
        XCTAssertNil(store.previewing)
        XCTAssertEqual(store.session?.phase, .resting)
        XCTAssertGreaterThan(audio.stops, 0)
    }

    /// 统计只累计运行时间，长时间暂停不会增加休息分钟数。
    func testHistoryExcludesPausedTime() {
        store.start(duration: 600)
        now.addTimeInterval(60)
        store.pause()
        now.addTimeInterval(3600)
        store.resume()
        now.addTimeInterval(60)
        store.finish(completed: false)
        XCTAssertEqual(store.records.first?.minutes, 2)
    }
    /// 无助眠音保留用户确认的尽力预约；模型测试不代表系统挂起后的声音验证。
    func testSilentBackgroundKeepsBestEffortAppointment() {
        store.preferences.sleepSound = .none
        store.start(duration: 60)
        let stops = audio.stops
        store.enteredBackground()
        XCTAssertEqual(store.session?.phase, .resting)
        XCTAssertEqual(audio.stops, stops)
    }

    /// 响铃阶段耳机重连自动续响，超过三分钟不会再自动补响。
    func testRingingReconnectAutomaticallyResumesWithinWindow() {
        store.start(duration: 1)
        now.addTimeInterval(1)
        store.tick()
        audio.disconnect()
        XCTAssertEqual(store.session?.phase, .blocked)
        audio.reconnect()
        XCTAssertEqual(store.session?.phase, .ringing)
        XCTAssertEqual(audio.starts, 2)
        audio.disconnect()
        now.addTimeInterval(181)
        audio.reconnect()
        XCTAssertEqual(store.session?.phase, .blocked)
        XCTAssertEqual(audio.starts, 2)
    }

    /// 震动仅在开启且正在响铃时按间隔触发，断连立即停止。
    func testOptionalVibrationFollowsAlarmState() {
        var vibrations = 0
        let hapticStore = RestStore(audio: audio, defaults: defaults, clock: { [unowned self] in self.now }, runsTimer: false, notificationsEnabled: false, vibrate: { vibrations += 1 })
        hapticStore.preferences.vibrationEnabled = true
        hapticStore.start(duration: 1)
        now.addTimeInterval(1)
        hapticStore.tick()
        XCTAssertEqual(vibrations, 1)
        hapticStore.tick()
        XCTAssertEqual(vibrations, 1)
        now.addTimeInterval(2)
        hapticStore.tick()
        XCTAssertEqual(vibrations, 2)
        audio.disconnect()
        now.addTimeInterval(2)
        hapticStore.tick()
        XCTAssertEqual(vibrations, 2)
    }

    /// 精确预设与不足一分钟的历史可正确保存。
    func testPrecisePresetAndHistoryPersistence() {
        store.addDurationPreset(15)
        store.addDurationPreset(15)
        store.preferences.minutes = 0
        store.preferences.seconds = 15
        store.start()
        now.addTimeInterval(15)
        store.tick()
        store.finish(completed: true)
        XCTAssertEqual(store.records.first?.seconds, 15)
        XCTAssertEqual(store.preferences.precisePresets, [15])
    }

    /// 有助眠音的后台会话保留原计时状态，不受页面生命周期干扰。
    func testAudibleBackgroundKeepsDeadline() {
        store.start(duration: 60)
        store.enteredBackground()
        XCTAssertEqual(store.session?.phase, .resting)
        now = now.addingTimeInterval(61)
        store.tick()
        XCTAssertEqual(store.session?.phase, .ringing)
    }

    /// 迁移旧默认预设，并保留用户主题选择和自定义时长。
    func testThemeAndDefaultPresetMigration() throws {
        var old = Preferences()
        old.presets = [15, 25, 45, 90]
        old.minutes = 37
        defaults.set(try JSONEncoder().encode(old), forKey: "preferences")
        let migrated = RestStore(audio: audio, defaults: defaults, runsTimer: false, notificationsEnabled: false)
        XCTAssertEqual(migrated.preferences.presets, [15, 30, 45, 60])
        XCTAssertEqual(migrated.preferences.minutes, 37)
        migrated.theme = .ocean
        let restored = RestStore(audio: audio, defaults: defaults, runsTimer: false, notificationsEnabled: false)
        XCTAssertEqual(restored.theme, .ocean)
    }

}
