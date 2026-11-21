import UIKit
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
        assertPreviewChrome(title: "小组件", note: "同一份记录", done: "完成")
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
        app.navigationBars.buttons["Beibei"].tap()
        requireAppearance("dark", settingsTab: "设置", homeTab: "今天", name: "12-zh-home-dark")
        requireAppearance("light", settingsTab: "设置", homeTab: "今天", name: "11-home-light")

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
        assertEnglishClock()
        let summary = element("home-compact-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 4))
        XCTAssertTrue(summary.label.contains("Formula"))
        captureCheckedAppearance("light", name: "16-english-home")
        app.buttons["show-widget-preview"].tap()
        let englishWidget = element("widget-summary")
        XCTAssertTrue(englishWidget.waitForExistence(timeout: 8))
        XCTAssertTrue(englishWidget.label.contains("Formula") || englishWidget.label.contains("Last feed"))
        assertPreviewChrome(title: "Widget", note: "same record", done: "Done")
        shot("18-english-widget")
        app.buttons["close-widget-preview"].tap()
        requireAppearance("dark", settingsTab: "Settings", homeTab: "Today", name: "17-english-dark")
        assertEnglishClock()
    }

    /// Changes Appearance in Settings, then refuses the screenshot unless the resolved scheme and the pixels agree.
    private func requireAppearance(_ expected: String, settingsTab: String, homeTab: String, name: String) {
        app.tabBars.buttons[settingsTab].tap()
        let option = appearanceControl(expected, chinese: settingsTab == "设置")
        for _ in 0..<5 where !option.exists {
            app.swipeUp()
        }
        XCTAssertTrue(option.waitForExistence(timeout: 4), "Appearance option \(expected) was not on screen")
        option.tap()
        app.tabBars.buttons[homeTab].tap()
        captureCheckedAppearance(expected, name: name)
    }

    private func appearanceControl(_ expected: String, chinese: Bool) -> XCUIElement {
        let identified = app.descendants(matching: .any)["appearance-\(expected)"]
        if identified.exists { return identified }
        let label: String
        if expected == "dark" {
            label = chinese ? "深色" : "Dark"
        } else {
            label = chinese ? "浅色" : "Light"
        }
        return app.buttons[label]
    }

    private func captureCheckedAppearance(_ expected: String, name: String) {
        let probe = app.descendants(matching: .any)["appearance-scheme"]
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: probe)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 8), .completed, "appearance stayed \(probe.label)")
        let screenshot = XCUIScreen.main.screenshot()
        let luma = averageLuminance(screenshot.image)
        if expected == "dark" {
            XCTAssertLessThan(luma, 0.45, "\(name) luminance \(luma) is still a light screen")
        } else {
            XCTAssertGreaterThan(luma, 0.60, "\(name) luminance \(luma) is still a dark screen")
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertEnglishClock() {
        let since = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Since '")).firstMatch
        XCTAssertTrue(since.waitForExistence(timeout: 6))
        XCTAssertFalse(since.label.contains("上午") || since.label.contains("下午"))
        XCTAssertTrue(since.label.contains("AM") || since.label.contains("PM"))
    }

    private func assertPreviewChrome(title: String, note: String, done: String) {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 4) || app.navigationBars[title].exists)
        let noteElement = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", note)).firstMatch
        XCTAssertTrue(noteElement.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons[done].waitForExistence(timeout: 4))
    }

    private func averageLuminance(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 1 }
        let width = 24
        let height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 1 }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0.0
        let count = width * height
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            sum += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return sum / Double(count)
    }

    /// Adds the Home Screen widget through Springboard. A missing control fails the test.
    /// The in-app preview is not accepted as the widget.
    ///
    /// A long-press on the icon opens a context menu, and on this simulator the
    /// accessibility server then stops answering. Pressing empty wallpaper is the
    /// path that enters edit mode without that menu.
    func testAddHomeScreenWidget() throws {
        app.launch()
        app.terminate()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        let icon = springboard.icons["宝宝小记"]
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        let wallpaper = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        wallpaper.press(forDuration: 1.2)
        let addButton = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Add Widget' OR label == '添加小组件' OR label == '+'")
        ).firstMatch
        let appeared = addButton.waitForExistence(timeout: 6)
        let shotName = appeared ? "14-widget-gallery" : "14-widget-gallery-missing"
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = shotName
        attachment.lifetime = .keepAlways
        add(attachment)
        guard appeared else {
            XCTFail("Home Screen widget was not added. Edit mode did not show an add control. See \(shotName). Skipping is not a successful add, and the in-app preview is not the widget.")
            return
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
