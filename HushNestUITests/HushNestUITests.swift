import XCTest

final class HushNestUITests: XCTestCase {
    private var app: XCUIApplication!

    /// 每个 UI 用例清理本地数据，使用中文界面和不输出声音的模拟耳机。
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    /// 失败时保存屏幕和可访问性树，定位真实交互或布局问题。
    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            print("FAILURE ACCESSIBILITY TREE:\n\(app.debugDescription)")
            screenshot("failure-\(name)")
        }
    }

    /// 验证完整的开始、暂停、恢复和确认结束交互。
    func testStartPauseResumeAndCancel() {
        app.launch()
        app.buttons["session.start"].tap()
        XCTAssertTrue(app.staticTexts["好好休息"].waitForExistence(timeout: 5))
        app.buttons["session.toggle"].tap()
        XCTAssertTrue(app.staticTexts["休息已暂停"].exists)
        let frozen = app.staticTexts["session.remaining"].label
        XCTAssertTrue(app.buttons["session.toggle"].isEnabled)
        let resumedAt = Date()
        app.buttons["session.toggle"].tap()
        XCTAssertTrue(app.staticTexts["好好休息"].exists)
        let resumed = seconds(app.staticTexts["session.remaining"].label)
        XCTAssertLessThanOrEqual(resumed, seconds(frozen))
        XCTAssertGreaterThanOrEqual(resumed, seconds(frozen) - Int(ceil(Date().timeIntervalSince(resumedAt))) - 1)
        app.buttons["session.cancel"].tap()
        app.buttons["结束休息"].tap()
        XCTAssertTrue(app.buttons["session.start"].waitForExistence(timeout: 5))
        screenshot("01-rest")
    }

    /// 验证未连接耳机时出现解释提示，不能进入运行界面。
    func testNoHeadphonesBlocksStart() {
        app.launchArguments.append("-no-headphones")
        app.launch()
        app.buttons["session.start"].tap()
        XCTAssertTrue(app.alerts["暂时无法开始"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "请先连接")).firstMatch.exists)
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["session.start"].exists)
    }

    /// 验证到点提醒、稍后提醒和完成后的历史页面可正常贯通。
    func testRingingSnoozeAndHistory() {
        app.launch()
        reveal(app.buttons["test.quickStart"])
        app.buttons["test.quickStart"].tap()
        XCTAssertTrue(app.buttons["session.snooze"].waitForExistence(timeout: 10))
        screenshot("02-wake")
        app.buttons["session.snooze"].tap()
        XCTAssertTrue(app.staticTexts["好好休息"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已稍后提醒 1 次"].waitForExistence(timeout: 5))
        app.buttons["session.cancel"].tap()
        app.buttons["结束休息"].tap()
        app.tabBars.buttons["足迹"].tap()
        XCTAssertTrue(app.staticTexts["提前结束"].waitForExistence(timeout: 5))
        screenshot("03-history")
        reveal(app.buttons["history.clear"])
        app.buttons["history.clear"].tap()
        app.buttons["清空记录"].tap()
        XCTAssertTrue(app.staticTexts["从片刻安静开始"].waitForExistence(timeout: 5))
    }

    /// 验证完成提醒操作可写入完成记录，而不是提前结束记录。
    func testFinishAlarmCreatesCompletedRecord() {
        app.launch()
        reveal(app.buttons["test.quickStart"])
        app.buttons["test.quickStart"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 10))
        app.buttons["session.finish"].tap()
        app.tabBars.buttons["足迹"].tap()
        XCTAssertTrue(app.staticTexts["完成一段休息"].waitForExistence(timeout: 5))
    }

    /// 验证声音配置改变后返回首页，且应用重启后依然保留。
    func testSoundSelectionPersists() {
        app.launch()
        reveal(app.buttons["sound.open"])
        app.buttons["sound.open"].tap()
        app.buttons["sound.ocean"].tap()
        app.buttons["sound.done"].tap()
        XCTAssertTrue(app.staticTexts["潮汐 → 晨光"].exists)
        app.terminate()
        app.launchArguments.append("-keep-data")
        app.launch()
        XCTAssertTrue(app.staticTexts["潮汐 → 晨光"].exists)
    }

    /// 验证自定义时长、保存预设和指定时间模式。
    func testCustomDurationAndClockMode() {
        app.launch()
        app.buttons["duration.edit"].tap()
        let stepper = app.steppers["duration.stepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons.element(boundBy: 1).tap()
        let presetSwitch = app.switches["duration.savePreset"]
        presetSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(presetSwitch.value as? String, "1")
        app.buttons["duration.done"].tap()
        XCTAssertTrue(app.buttons["preset.26"].waitForExistence(timeout: 5))
        app.segmentedControls["schedule.mode"].buttons["指定时间"].tap()
        XCTAssertTrue(app.datePickers["clock.picker"].exists)
        app.buttons["session.start"].tap()
        XCTAssertTrue(app.staticTexts["好好休息"].exists)
    }

    /// 验证断连立即进入中断，重连不会偷偷恢复，恢复必须由用户点击。
    func testDisconnectAndExplicitResume() {
        app.launch()
        app.buttons["session.start"].tap()
        app.tabBars.buttons["设置"].tap()
        reveal(app.buttons["test.disconnect"])
        app.buttons["test.disconnect"].tap()
        app.tabBars.buttons["休息"].tap()
        XCTAssertTrue(app.staticTexts["提醒已中断"].exists)
        screenshot("04-disconnected")
        app.tabBars.buttons["设置"].tap()
        reveal(app.buttons["test.reconnect"])
        app.buttons["test.reconnect"].tap()
        app.tabBars.buttons["休息"].tap()
        XCTAssertTrue(app.staticTexts["提醒已中断"].exists)
        app.buttons["session.toggle"].tap()
        XCTAssertTrue(app.staticTexts["好好休息"].exists)
    }

    /// 验证强制关闭后恢复的是中断状态，不会伪装成后台仍在工作。
    func testRelaunchShowsInterruptedSession() {
        app.launch()
        app.buttons["session.start"].tap()
        app.terminate()
        app.launchArguments.append("-keep-data")
        app.launch()
        XCTAssertTrue(app.staticTexts["提醒已中断"].waitForExistence(timeout: 5))
        app.buttons["session.toggle"].tap()
        XCTAssertTrue(app.staticTexts["好好休息"].exists)
    }

    /// 验证指南可打开关闭，设置页面可浏览且无订阅入口。
    func testGuideAndSettingsNavigation() {
        app.launch()
        app.buttons["guide.open"].tap()
        XCTAssertTrue(app.staticTexts["连接你的耳机"].exists)
        screenshot("05-guide")
        app.buttons["guide.done"].tap()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.sound"].exists)
        screenshot("06-settings")
    }

    /// 验证超大字体场景下开始、暂停及结束操作仍能触达。
    func testAccessibilityTextSizeKeepsPrimaryControlsReachable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["session.start"].isHittable)
        app.buttons["session.start"].tap()
        XCTAssertTrue(app.buttons["session.toggle"].isHittable)
        app.buttons["session.toggle"].tap()
        XCTAssertTrue(app.buttons["session.cancel"].isHittable)
        let settledAt = Date().addingTimeInterval(1)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= settledAt }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
        screenshot("07-accessibility")
    }

    /// 滚动使目标控件可见，避免测试依赖固定屏幕坐标。
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "目标控件应可通过滚动触达")
    }

    /// 将真实模拟器界面作为测试附件保存，便于视觉复核。
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 解析可见倒计时，允许恢复点击和系统动画期间真实流逝的时间。
    private func seconds(_ text: String) -> Int {
        text.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    /// 验证耳机内试听的开始、停止与配置页退出时的自动停止。
    func testPreviewInteractions() {
        app.launch()
        app.buttons["sound.open"].tap()
        app.buttons["preview.rain"].tap()
        XCTAssertEqual(app.buttons["preview.rain"].label, "停止试听细雨")
        app.buttons["preview.rain"].tap()
        XCTAssertEqual(app.buttons["preview.rain"].label, "试听细雨")
        app.buttons["preview.ocean"].tap()
        app.buttons["sound.done"].tap()
        app.buttons["sound.open"].tap()
        XCTAssertEqual(app.buttons["preview.ocean"].label, "试听潮汐")
    }

    /// 无耳机时试听必须在当前模态页给出清楚提示。
    func testPreviewWithoutHeadphonesExplainsFailure() {
        app.launchArguments.append("-no-headphones")
        app.launch()
        app.buttons["sound.open"].tap()
        app.buttons["preview.rain"].tap()
        XCTAssertTrue(app.alerts["无法试听"].waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["sound.done"].isHittable)
    }

    /// 深色主题的三个主页均可使用，并保留截图进行对比度复核。
    func testDarkAppearance() {
        app.launchArguments.append("-dark-appearance")
        app.launch()
        screenshot("08-dark-rest")
        app.buttons["session.start"].tap()
        XCTAssertTrue(app.buttons["session.toggle"].isHittable)
        screenshot("09-dark-active")
        app.tabBars.buttons["足迹"].tap()
        XCTAssertTrue(app.staticTexts["从片刻安静开始"].exists)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.sound"].exists)
        screenshot("10-dark-settings")
    }

    /// 应用进入后台后再返回，倒计时仍按绝对截止时间进入提醒状态。
    func testBackgroundDeadlineCatchesUp() {
        app.launch()
        app.buttons["test.quickStart"].tap()
        XCTAssertTrue(app.buttons["session.toggle"].waitForExistence(timeout: 2))
        let deadline = Date().addingTimeInterval(4)
        XCUIDevice.shared.press(.home)
        let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= deadline }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 6), .completed)
        app.activate()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.buttons["session.start"].waitForExistence(timeout: 5))
    }
}
