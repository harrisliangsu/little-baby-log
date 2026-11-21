import XCTest

/// Simulator smoke test: create a baby, log formula, diapers, sleep, and nursing,
/// relaunch, and check the widget snapshot the extension reads.
final class SmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testLogPersistAndWidgetSnapshot() throws {
        app.launch()
        shot("01-launch")

        let name = app.textFields["baby-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Beibei")
        app.buttons["start-tracking"].tap()

        let formula = element("summary-formula")
        XCTAssertTrue(formula.waitForExistence(timeout: 8))
        XCTAssertTrue(formula.label.contains("还没有"))
        shot("02-empty-cards")

        app.buttons["show-widget-preview"].tap()
        let emptyWidget = element("widget-summary")
        XCTAssertTrue(emptyWidget.waitForExistence(timeout: 8))
        XCTAssertTrue(emptyWidget.label.contains("还没有记录") || emptyWidget.label.contains("奶粉0次"))
        shot("03-widget-empty")
        app.buttons["close-widget-preview"].tap()

        logFormula(millilitres: "120")
        tap("add-wet")
        tap("add-dirty")
        tap("add-diaper-change")
        tap("add-sleep")
        app.swipeDown()
        app.swipeDown()
        logNursing()

        XCTAssertTrue(formula.label.contains("1次"))
        XCTAssertTrue(formula.label.contains("120"))
        XCTAssertTrue(formula.label.contains("24小时"))
        XCTAssertTrue(element("summary-wet").label.contains("1次"))
        XCTAssertTrue(element("summary-dirty").label.contains("1次"))
        XCTAssertTrue(element("summary-change").label.contains("1次"))
        XCTAssertTrue(element("summary-sleep").label.contains("睡眠中"))
        XCTAssertTrue(element("summary-breast").label.contains("1次"))
        shot("04-after-logging")

        app.buttons["show-widget-preview"].tap()
        let widget = element("widget-summary")
        XCTAssertTrue(widget.waitForExistence(timeout: 8))
        XCTAssertTrue(widget.label.contains("奶粉1次"))
        XCTAssertTrue(widget.label.contains("120"))
        XCTAssertTrue(widget.label.contains("24小时"))
        XCTAssertTrue(widget.label.contains("小便1"))
        XCTAssertTrue(widget.label.contains("睡眠1"))
        shot("05-widget-filled")
        app.buttons["close-widget-preview"].tap()

        relaunchFromHomeScreen()

        let kept = element("summary-formula")
        XCTAssertTrue(kept.waitForExistence(timeout: 8))
        XCTAssertTrue(kept.label.contains("120"))
        XCTAssertTrue(element("summary-wet").label.contains("1次"))
        XCTAssertTrue(element("summary-sleep").label.contains("1次"))
        shot("06-after-relaunch")

        app.buttons["show-widget-preview"].tap()
        let again = element("widget-summary")
        XCTAssertTrue(again.waitForExistence(timeout: 8))
        XCTAssertTrue(again.label.contains("奶粉1次"))
        XCTAssertTrue(again.label.contains("120"))
        shot("07-widget-after-relaunch")
        app.buttons["close-widget-preview"].tap()

        app.buttons["summary-formula"].tap()
        let total = element("timeline-total")
        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertTrue(total.label.contains("120"))
        XCTAssertTrue(total.label.contains("1次"))
        shot("09-timeline")
        XCUIDevice.shared.appearance = .dark
        shot("10-timeline-dark")
        XCUIDevice.shared.appearance = .light
        app.navigationBars.buttons["Beibei"].tap()
        shot("11-home-light")

        app.tabBars.buttons["设置"].tap()
        let languagePicker = app.buttons["app-language"]
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 6))
        languagePicker.tap()
        let english = app.buttons["英文"]
        XCTAssertTrue(english.waitForExistence(timeout: 4))
        english.tap()
        if app.tabBars.buttons["Today"].waitForExistence(timeout: 4) {
            app.tabBars.buttons["Today"].tap()
        }
        let englishHome = element("summary-formula")
        XCTAssertTrue(englishHome.waitForExistence(timeout: 6))
        XCTAssertTrue(englishHome.label.contains("Formula") || englishHome.label.contains("Last"))
        shot("16-english-home")
        XCUIDevice.shared.appearance = .dark
        shot("17-english-dark")
        app.buttons["show-widget-preview"].tap()
        let englishWidget = element("widget-summary")
        XCTAssertTrue(englishWidget.waitForExistence(timeout: 8))
        XCTAssertTrue(englishWidget.label.contains("Formula") || englishWidget.label.contains("Last feed"))
        shot("18-english-widget")
        app.buttons["close-widget-preview"].tap()
    }

    /// Tries to add the real Home Screen widget from Springboard. If iOS 26 does not expose
    /// the gallery control to the test runner, the test is skipped and the screen is attached.
    func testAddHomeScreenWidget() throws {
        app.launch()
        app.terminate()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        let icon = springboard.icons["宝宝小记"]
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        icon.press(forDuration: 1.3)
        let wallpaper = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        wallpaper.press(forDuration: 1.4)
        let menuLabels = ["Edit Home Screen", "编辑主屏幕"]
        for label in menuLabels where springboard.buttons[label].waitForExistence(timeout: 1) {
            springboard.buttons[label].tap()
            break
        }
        let addLabels = ["Add Widget", "Add", "添加小组件", "添加"]
        var addButton = springboard.buttons["Add Widget"]
        for label in addLabels where springboard.buttons[label].exists {
            addButton = springboard.buttons[label]
            break
        }
        let seen = springboard.buttons.allElementsBoundByIndex.prefix(20).map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
        let shotName = addButton.waitForExistence(timeout: 4) ? "14-widget-gallery" : "14-widget-gallery-missing"
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = shotName
        attachment.lifetime = .keepAlways
        add(attachment)
        guard addButton.waitForExistence(timeout: 1) else {
            throw XCTSkip("Springboard did not show an Add Widget control. Visible buttons: \(seen). See attachment \(shotName). The in-app preview is not this widget.")
        }
        addButton.tap()
        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 4) {
            search.tap()
            search.typeText("宝宝小记")
        }
        let choice = springboard.cells.matching(NSPredicate(format: "label CONTAINS '宝宝小记' OR label CONTAINS 'Little Baby Log'")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 8))
        choice.tap()
        let confirm = springboard.buttons["Add Widget"].exists ? springboard.buttons["Add Widget"] : springboard.buttons["添加小组件"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6))
        confirm.tap()
        springboard.activate()
        let placed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        placed.name = "15-home-screen-widget"
        placed.lifetime = .keepAlways
        add(placed)
    }

    /// Xcode 26 times out when the test runner launches the same app a second time
    /// through the debugger. Opening the home-screen icon is a real restart.
    private func relaunchFromHomeScreen() {
        app.terminate()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        let icon = springboard.icons["宝宝小记"]
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        home.name = "08-home-screen"
        home.lifetime = .keepAlways
        add(home)
        icon.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        if !button.waitForExistence(timeout: 2) || !button.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.tap()
    }

    private func logFormula(millilitres: String) {
        app.buttons["add-formula"].tap()
        let amount = app.textFields["bottle-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText(millilitres)
        let save = app.buttons["save-entry"]
        if !save.isHittable, app.buttons["完成"].exists {
            app.buttons["完成"].tap()
        }
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        XCTAssertTrue(element("summary-formula").waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func logNursing() {
        app.buttons["add-breast"].tap()
        let left = app.buttons["breast-left"]
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        left.tap()
        let started = expectation(description: "nursing elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { started.fulfill() }
        wait(for: [started], timeout: 4)
        let done = app.buttons["breast-done"]
        if !done.isHittable {
            app.swipeUp()
        }
        done.tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
