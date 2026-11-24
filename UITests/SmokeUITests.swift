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
        app.launchArguments += ["-lbl-ui-reset"]
        app.launch()
        shot("01-launch")

        createBabyNamed("Beibei")

        let formula = element("summary-formula")
        XCTAssertTrue(formula.waitForExistence(timeout: 8))
        XCTAssertTrue(formula.label.contains("还没有"))
        XCTAssertFalse(app.staticTexts["回顾"].exists)
        XCTAssertFalse(app.staticTexts["时间线"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["add-formula"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["add-wet"].frame.height, 44)
        shot("02-empty-cards")

        openWidgetPreview()
        let emptyWidget = element("widget-summary")
        XCTAssertTrue(emptyWidget.waitForExistence(timeout: 8))
        XCTAssertTrue(emptyWidget.label.contains("还没有记录") || emptyWidget.label.contains("奶粉0次"))
        let emptyFace = element("widget-face-small")
        XCTAssertTrue(emptyFace.waitForExistence(timeout: 4))
        XCTAssertTrue(emptyFace.label.contains("还没有"))
        assertPreviewChrome(title: "小组件", done: "完成")
        shot("03-widget-empty")
        closeWidgetPreview()

        logFormula(millilitres: "120")
        saveCurrentForm("add-wet")
        saveCurrentForm("add-dirty")
        saveCurrentForm("add-diaper-change")
        saveCurrentForm("add-sleep")
        app.swipeDown()
        app.swipeDown()
        logNursing()

        XCTAssertTrue(formula.label.contains("120"))
        XCTAssertFalse(formula.label.contains("今日"))
        XCTAssertTrue(loggedAge(element("summary-wet").label), "wet card stayed \(element("summary-wet").label) \(saveTrace)")
        XCTAssertTrue(loggedAge(element("summary-dirty").label), "dirty card stayed \(element("summary-dirty").label) \(saveTrace)")
        XCTAssertTrue(loggedAge(element("summary-change").label), "change card stayed \(element("summary-change").label) \(saveTrace)")
        let breast = element("summary-breast")
        let showedDuration = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "1分钟"),
            object: breast
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [showedDuration], timeout: 4),
            .completed,
            "breast card stayed \(breast.label) \(saveTrace)"
        )
        let sleep = requireSleepCard()
        XCTAssertTrue(loggedAge(sleep.label), "sleep card stayed \(sleep.label) \(saveTrace)")
        XCTAssertFalse(sleep.label.contains("还没有"), "sleep card stayed \(sleep.label)")
        shot("04-after-logging")

        openWidgetPreview()
        let widget = element("widget-summary")
        XCTAssertTrue(widget.waitForExistence(timeout: 8))
        XCTAssertTrue(widget.label.contains("奶粉1次"))
        XCTAssertTrue(widget.label.contains("120"))
        XCTAssertTrue(widget.label.contains("24小时"))
        XCTAssertTrue(widget.label.contains("小便1"))
        XCTAssertTrue(widget.label.contains("睡眠1"))
        let mediumFace = element("widget-face-medium")
        XCTAssertTrue(mediumFace.waitForExistence(timeout: 4))
        XCTAssertTrue(mediumFace.label.contains("今日"))
        XCTAssertTrue(mediumFace.label.contains("120"))
        XCTAssertTrue(mediumFace.label.contains("小便"))
        XCTAssertFalse(mediumFace.label.contains("formula"))
        XCTAssertFalse(mediumFace.label.contains("ago"))
        XCTAssertFalse(mediumFace.label.contains("Next feed"))
        let sized = element("widget-face-check")
        XCTAssertTrue(sized.waitForExistence(timeout: 4))
        XCTAssertTrue(sized.label.contains("距上次"))
        XCTAssertFalse(sized.label.contains("…"))
        XCTAssertFalse(sized.label.contains("formula"))
        shot("05-widget-filled")
        closeWidgetPreview()

        relaunchFromHomeScreen()

        let kept = element("summary-formula")
        XCTAssertTrue(kept.waitForExistence(timeout: 8))
        XCTAssertTrue(kept.label.contains("120"))
        XCTAssertTrue(loggedAge(element("summary-wet").label))
        let sleepKept = requireSleepCard()
        XCTAssertFalse(sleepKept.label.contains("还没有"), "sleep card stayed \(sleepKept.label)")
        XCTAssertTrue(loggedAge(sleepKept.label), "sleep card stayed \(sleepKept.label)")
        shot("06-after-relaunch")

        openWidgetPreview()
        let again = element("widget-summary")
        XCTAssertTrue(again.waitForExistence(timeout: 8))
        XCTAssertTrue(again.label.contains("奶粉1次"))
        XCTAssertTrue(again.label.contains("120"))
        shot("07-widget-after-relaunch")
        closeWidgetPreview()

        app.buttons["summary-formula"].tap()
        let total = element("timeline-total")
        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertTrue(total.label.contains("120"))
        XCTAssertTrue(total.label.contains("1次"))
        shot("09-timeline")
        app.navigationBars.buttons["Beibei"].tap()
        requireAppearance("dark", settingsTab: "设置", homeTab: "今天", name: "12-zh-home-dark")
        requireAppearance("light", settingsTab: "设置", homeTab: "今天", name: "11-home-light")

        returnToSettingsHub(tabTitle: "设置")
        let languageModule = app.descendants(matching: .any)["settings-module-language"]
        XCTAssertTrue(languageModule.waitForExistence(timeout: 4), "settings-module-language")
        languageModule.tap()
        let languagePicker = app.buttons["app-language"]
        for _ in 0..<6 where !languagePicker.exists {
            app.swipeDown()
        }
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 6))
        languagePicker.tap()
        let english = app.buttons["英文"]
        XCTAssertTrue(english.waitForExistence(timeout: 4))
        english.tap()
        if tab("Today").waitForExistence(timeout: 4) {
            tab("Today").tap()
        }
        let englishHome = element("summary-formula")
        XCTAssertTrue(englishHome.waitForExistence(timeout: 6))
        XCTAssertTrue(englishHome.label.contains("Formula") || englishHome.label.contains("Last"))
        assertEnglishClock()
        captureCheckedAppearance("light", name: "16-english-home")
        openWidgetPreview()
        let englishWidget = element("widget-summary")
        XCTAssertTrue(englishWidget.waitForExistence(timeout: 8))
        XCTAssertTrue(englishWidget.label.contains("Formula") || englishWidget.label.contains("Last feed"))
        let englishFace = element("widget-face-small")
        XCTAssertTrue(englishFace.waitForExistence(timeout: 4))
        XCTAssertTrue(englishFace.label.contains("Formula") || englishFace.label.contains("Since last"))
        XCTAssertFalse(englishFace.label.contains("奶粉"))
        XCTAssertFalse(englishFace.label.contains("距上次"))
        assertPreviewChrome(title: "Widget", done: "Done")
        shot("18-english-widget")
        closeWidgetPreview()
        requireAppearance("dark", settingsTab: "Settings", homeTab: "Today", name: "17-english-dark")
        assertEnglishClock()
    }

    /// Changes Appearance in Settings, then refuses the screenshot unless the resolved scheme and the pixels agree.
    private func requireAppearance(_ expected: String, settingsTab: String, homeTab: String, name: String) {
        returnToSettingsHub(tabTitle: settingsTab)
        let appearanceModule = app.descendants(matching: .any)["settings-module-appearance"]
        XCTAssertTrue(appearanceModule.waitForExistence(timeout: 4), "settings-module-appearance")
        appearanceModule.tap()
        let option = appearanceControl(expected, chinese: settingsTab == "设置")
        for _ in 0..<8 where !option.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(option.waitForExistence(timeout: 4), "Appearance option \(expected) was not on screen")
        option.tap()
        let probe = app.descendants(matching: .any)["appearance-scheme"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: probe)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 8), .completed, "appearance stayed \(probe.label) after choosing \(expected)")
        XCTAssertEqual(app.descendants(matching: .any)["appearance-\(expected)"].value as? String, "selected")
        XCTAssertEqual(app.descendants(matching: .any)["style-classic"].value as? String, "selected")
        XCTAssertEqual(app.descendants(matching: .any)["style-liquidGlass"].value as? String, "unselected")
        let style = app.descendants(matching: .any)["style-applied"]
        XCTAssertEqual(style.label, "classic")
        if name == "review-25-today-dark" {
            shot("review-26-appearance-groups")
            app.descendants(matching: .any)["style-liquidGlass"].tap()
            let glass = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "liquidGlass"), object: style)
            XCTAssertEqual(XCTWaiter().wait(for: [glass], timeout: 8), .completed, "style stayed \(style.label)")
            XCTAssertEqual(probe.label, expected, "style changed the appearance")
            XCTAssertEqual(app.descendants(matching: .any)["appearance-\(expected)"].value as? String, "selected")
            shot("review-27-liquid-glass")
            app.descendants(matching: .any)["style-classic"].tap()
            let classic = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "classic"), object: style)
            XCTAssertEqual(XCTWaiter().wait(for: [classic], timeout: 8), .completed, "style stayed \(style.label)")
        }
        tab(homeTab).tap()
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
        let since = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ago' OR label CONTAINS 'Just now' OR label BEGINSWITH 'Since '")).firstMatch
        XCTAssertTrue(since.waitForExistence(timeout: 6))
        XCTAssertFalse(since.label.contains("上午") || since.label.contains("下午"))
        XCTAssertFalse(since.label.contains("分钟前"))
    }

    private func assertPreviewChrome(title: String, done: String) {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 4) || app.navigationBars[title].exists)
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

    /// Adds 宝宝小记 from the widget gallery and checks a real record appears on the Home Screen.
    /// The CI simulator's SpringBoard gallery is often empty, including system widgets.
    /// This check is manual. It does not gate a TestFlight upload. Set LBL_HOME_SCREEN_WIDGET=1 to run it.
    func testAddHomeScreenWidget() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LBL_HOME_SCREEN_WIDGET"] == "1",
            "Home Screen widget gallery check is manual. The CI simulator gallery is unstable and does not gate release."
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        // WidgetKit often omits the extension from the gallery until the app has been open.
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        app.terminate()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        let icon = springboard.icons["宝宝小记"]
        XCTAssertTrue(icon.waitForExistence(timeout: 15))

        let wallpaper = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        wallpaper.press(forDuration: 1.2)
        let edit = requireControl(springboard, labels: ["Edit", "编辑"], shot: "14-edit-mode")
        edit.tap()
        let addGallery = requireControl(springboard, labels: ["Add Widget", "添加小组件"], shot: "14-edit-menu")
        addGallery.tap()
        shotSpringboard("14-widget-gallery")

        addGalleryWidget(springboard, query: "宝宝小记", choice: "宝宝小记", swipes: 0)
        finishEditing(springboard)
        assertEmptyWidget(springboard)
        shotSpringboard("15-small-empty")

        openWidgetGallery(springboard)
        addGalleryWidget(springboard, query: "宝宝小记", choice: "宝宝小记", swipes: 1)
        finishEditing(springboard)
        shotSpringboard("15-medium-empty")

        openWidgetGallery(springboard)
        addGalleryWidget(springboard, query: "宝宝小记", choice: "宝宝小记", swipes: 2)
        finishEditing(springboard)
        shotSpringboard("15-large-empty")
        assertWidgetSizes(springboard)

        let appIcon = homeAppIcon(springboard)
        XCTAssertNotNil(appIcon, "The app icon was not separate from the widget.\n\(widgetFrameText(springboard))")
        appIcon?.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        if app.textFields["baby-name"].waitForExistence(timeout: 4) {
            createBabyNamed("Beibei")
        }
        logFormula(millilitres: "120")
        saveCurrentForm("add-wet")
        app.terminate()
        springboard.activate()
        let updated = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '120'")).firstMatch
        let showedUpdate = updated.waitForExistence(timeout: 25)
        shotSpringboard("15-home-screen-widget-after")
        XCTAssertTrue(showedUpdate, "The Home Screen widget did not show the new 120 ml record.")
        XCTAssertFalse(springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'formula'")).firstMatch.exists)
        XCTAssertFalse(springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Next feed'")).firstMatch.exists)
        XCTAssertFalse(springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'minutes ago'")).firstMatch.exists)
        let pee = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '小便'")).firstMatch
        var showedPee = pee.waitForExistence(timeout: 4)
        if !showedPee {
            for page in 1...3 {
                springboard.swipeLeft()
                shotSpringboard("15-after-page-\(page)")
                if pee.waitForExistence(timeout: 8) {
                    showedPee = true
                    break
                }
            }
        }
        XCTAssertTrue(showedPee, "The medium or large widget did not show 小便 next to the feed.")

        XCUIDevice.shared.appearance = .dark
        shotSpringboard("15-widget-dark")
        XCUIDevice.shared.appearance = .light

        let small = widget(on: springboard, matching: { $0.width > 120 && $0.width < 210 && $0.height < 230 })
        XCTAssertNotNil(small, "No small widget to tap.\n\(widgetFrameText(springboard))")
        small?.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(element("composer-card").waitForExistence(timeout: 12))
        XCTAssertEqual(element("composer-card").label, "formula")
        XCTAssertTrue(element("composer-baby").label.contains("Beibei"))
        XCTAssertTrue(app.buttons["save-entry"].exists)
        app.buttons["取消"].tap()

        springboard.activate()
        let medium = widget(on: springboard, matching: { $0.width >= 210 && $0.height < 260 })
        let peeButton = springboard.buttons.matching(NSPredicate(format: "label CONTAINS '小便'")).firstMatch
        if peeButton.waitForExistence(timeout: 4) {
            peeButton.tap()
        } else if let medium {
            medium.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45)).tap()
        } else {
            XCTFail("No medium widget tap target.\n\(widgetFrameText(springboard))")
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(element("composer-card").waitForExistence(timeout: 12))
        XCTAssertEqual(element("composer-card").label, "wet")
        XCTAssertTrue(element("composer-baby").label.contains("Beibei"))
        XCTAssertTrue(app.buttons["save-entry"].exists)
        app.buttons["取消"].tap()

        let formula = element("summary-formula")
        XCTAssertTrue(formula.waitForExistence(timeout: 8))
        XCTAssertTrue(formula.label.contains("120"))
        XCTAssertTrue(loggedAge(element("summary-wet").label))
        XCTAssertFalse(element("summary-wet").label.contains("2次"))
    }

    private func openWidgetGallery(_ springboard: XCUIApplication) {
        if springboard.buttons["Edit"].exists || springboard.buttons["编辑"].exists {
            requireControl(springboard, labels: ["Edit", "编辑"], shot: "14-edit-mode-again").tap()
        } else {
            let wallpaper = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            wallpaper.press(forDuration: 1.2)
            requireControl(springboard, labels: ["Edit", "编辑"], shot: "14-edit-mode-again").tap()
        }
        requireControl(springboard, labels: ["Add Widget", "添加小组件"], shot: "14-edit-menu-again").tap()
    }

    private func addGalleryWidget(_ springboard: XCUIApplication, query: String, choice: String, swipes: Int = 0) {
        func listed(_ name: String) -> XCUIElement {
            springboard.cells.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        }
        var match = listed(choice)
        if !match.waitForExistence(timeout: 4) {
            waitForGalleryEntries(springboard)
            let search = springboard.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 8), "Widget gallery did not show a search field.\n\(visibleControls(springboard))")
            searchForWidget(springboard, search: search, query: query)
            match = listed(choice)
            if !match.waitForExistence(timeout: 8) {
                if springboard.buttons["Clear text"].exists { springboard.buttons["Clear text"].tap() }
                searchForWidget(springboard, search: search, query: "LittleBabyLog")
                match = listed("LittleBabyLog")
                if !match.exists { match = listed(choice) }
            }
            XCTAssertTrue(match.waitForExistence(timeout: 12), "Gallery has no \(choice).\n\(visibleControls(springboard))")
        }
        match.tap()
        selectGallerySize(springboard, swipes: swipes)
        let confirm = requireControl(springboard, labels: ["Add Widget", "添加小组件"], shot: "14-gallery-\(query)")
        confirm.tap()
    }

    /// The gallery sheet can open blank. Searching then stays on "No Results" for every widget, including the system's.
    /// Close it and open it again once the list has had a chance to load.
    private func waitForGalleryEntries(_ springboard: XCUIApplication) {
        if springboard.cells.firstMatch.waitForExistence(timeout: 8) { return }
        let lower = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        lower.press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        if springboard.cells.firstMatch.waitForExistence(timeout: 4) { return }
        _ = tapControl(springboard, labels: ["Close", "Done", "完成"], timeout: 2)
        if springboard.buttons["Edit"].waitForExistence(timeout: 3) || springboard.buttons["编辑"].exists {
            _ = tapControl(springboard, labels: ["Edit", "编辑"], timeout: 3)
        } else {
            let wallpaper = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            wallpaper.press(forDuration: 1.2)
            _ = tapControl(springboard, labels: ["Edit", "编辑"], timeout: 4)
        }
        _ = tapControl(springboard, labels: ["Add Widget", "添加小组件"], timeout: 6)
        _ = springboard.cells.firstMatch.waitForExistence(timeout: 12)
    }

    private func searchForWidget(_ springboard: XCUIApplication, search: XCUIElement, query: String) {
        search.tap()
        search.typeText(query)
        _ = tapControl(springboard, labels: ["search", "Search", "搜索"], timeout: 2)
    }

    /// Small is the gallery's first page. Medium and large are the next pages, or a size button when one is exposed.
    private func selectGallerySize(_ springboard: XCUIApplication, swipes: Int) {
        let labels: [String]
        switch swipes {
        case 1: labels = ["Medium", "中号"]
        case 2: labels = ["Large", "大号"]
        default: return
        }
        if tapControl(springboard, labels: labels, timeout: 2) { return }
        let preview = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.36))
        let aside = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.36))
        for _ in 0..<swipes {
            preview.press(forDuration: 0.08, thenDragTo: aside)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    private func finishEditing(_ springboard: XCUIApplication) {
        _ = tapControl(springboard, labels: ["Done", "完成"], timeout: 4)
    }

    private func assertEmptyWidget(_ springboard: XCUIApplication) {
        let empty = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '还没有记录' OR label CONTAINS '打开宝宝小记' OR label CONTAINS 'Nothing logged yet' OR label CONTAINS '还没有'")
        ).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 20), "The Home Screen widget is blank. Empty data must show the empty-state words, not only the name under a white square.")
    }

    private func assertWidgetSizes(_ springboard: XCUIApplication) {
        var frames = widgetFrames(springboard)
        if !frames.contains(where: { $0.height > 280 }) {
            springboard.swipeLeft()
            frames = widgetFrames(springboard)
            springboard.swipeRight()
        }
        attachText("15-widget-frames", frames.map { "\($0.width)x\($0.height)" }.joined(separator: "\n"))
        XCTAssertTrue(frames.contains { $0.width >= 210 && $0.height < 280 }, "Medium widget was not on the Home Screen.\n\(widgetFrameText(springboard))")
        XCTAssertTrue(frames.contains { $0.height > 280 }, "Large widget was not on the Home Screen.\n\(widgetFrameText(springboard))")
    }

    /// The app icon shares the widget's name. Off-screen copies report a zero frame and are not tappable.
    private func homeAppIcon(_ springboard: XCUIApplication) -> XCUIElement? {
        func match() -> XCUIElement? {
            let named = springboard.icons.matching(NSPredicate(format: "label == %@", "宝宝小记"))
            for index in 0..<min(named.count, 8) {
                let element = named.element(boundBy: index)
                let frame = element.frame
                guard element.exists, element.isHittable else { continue }
                guard frame.width > 44, frame.width < 120, frame.height > 44 else { continue }
                return element
            }
            return nil
        }
        if let found = match() { return found }
        springboard.swipeLeft()
        if let found = match() { return found }
        springboard.swipeRight()
        springboard.swipeRight()
        return match()
    }

    private func widget(on springboard: XCUIApplication, matching matches: (CGRect) -> Bool) -> XCUIElement? {
        let named = springboard.icons.matching(NSPredicate(format: "label CONTAINS %@", "宝宝小记"))
        for index in 0..<min(named.count, 8) {
            let element = named.element(boundBy: index)
            guard element.exists, element.isHittable, matches(element.frame) else { continue }
            return element
        }
        return nil
    }

    private func widgetFrames(_ springboard: XCUIApplication) -> [CGRect] {
        let named = springboard.icons.matching(NSPredicate(format: "label CONTAINS %@", "宝宝小记"))
        var frames: [CGRect] = []
        for index in 0..<min(named.count, 6) {
            let element = named.element(boundBy: index)
            guard element.exists, element.frame.width > 120 else { continue }
            frames.append(element.frame)
        }
        return frames
    }

    private func widgetFrameText(_ springboard: XCUIApplication) -> String {
        widgetFrames(springboard).map { "\($0.width)x\($0.height)" }.joined(separator: ", ")
    }

    /// Removes the large widget we just added. Its delete badge has no name, so the
    /// badge is the small button at that widget's corner, not a badge on another icon.
    private func removeOnlyTheTestWidget(_ springboard: XCUIApplication, name: String) {
        let named = springboard.icons.matching(NSPredicate(format: "label == %@", name))
        var widget: XCUIElement?
        var width: CGFloat = 0
        for index in 0..<min(named.count, 4) {
            let element = named.element(boundBy: index)
            guard element.exists, element.frame.width > width else { continue }
            width = element.frame.width
            widget = element
        }
        guard let widget, width > 120 else {
            attachTree("15-remove-not-named", springboard)
            shotSpringboard("15-remove-not-named")
            XCTFail("Could not find a large \(name) widget to remove.")
            return
        }
        let corner = CGPoint(x: widget.frame.minX, y: widget.frame.minY)
        let badges = springboard.buttons.allElementsBoundByIndex.filter { $0.frame.width < 44 && $0.frame.height < 44 }
        let nearest = badges.min { lhs, rhs in
            hypot(lhs.frame.midX - corner.x, lhs.frame.midY - corner.y)
                < hypot(rhs.frame.midX - corner.x, rhs.frame.midY - corner.y)
        }
        guard let nearest, hypot(nearest.frame.midX - corner.x, nearest.frame.midY - corner.y) < 40 else {
            attachTree("15-remove-not-named", springboard)
            shotSpringboard("15-remove-not-named")
            XCTFail("No delete badge sits on the \(name) widget. Other icons were left alone.")
            return
        }
        nearest.tap()
        _ = tapControl(springboard, labels: ["Remove Widget", "Remove", "移除小组件", "删除小组件"], timeout: 4)
    }

    private func requireControl(_ app: XCUIApplication, labels: [String], shot name: String) -> XCUIElement {
        if let found = waitControl(app, labels: labels, timeout: 8) {
            return found
        }
        attachTree(name, app)
        shotSpringboard(name)
        XCTFail("Missing \(labels.joined(separator: " / ")).\n\(visibleControls(app))")
        return app.buttons[labels[0]]
    }

    private func tapControl(_ app: XCUIApplication, labels: [String], timeout: TimeInterval) -> Bool {
        guard let found = waitControl(app, labels: labels, timeout: timeout) else { return false }
        found.tap()
        return true
    }

    private func waitControl(_ app: XCUIApplication, labels: [String], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let predicate = NSPredicate(format: "label CONTAINS %@", label)
                for query in [app.buttons, app.menuItems] {
                    let match = query.matching(predicate).firstMatch
                    if match.exists { return match }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    private func visibleControls(_ app: XCUIApplication) -> String {
        func lines(_ query: XCUIElementQuery, _ kind: String) -> [String] {
            query.allElementsBoundByIndex.prefix(40).compactMap { element in
                let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { return nil }
                return "\(kind) \(label)"
            }
        }
        return (lines(app.buttons, "button") + lines(app.menuItems, "menu") + lines(app.cells, "cell") + lines(app.searchFields, "search"))
            .joined(separator: "\n")
    }

    private func attachTree(_ name: String, _ app: XCUIApplication) {
        attachText(name, visibleControls(app))
    }

    private func attachText(_ name: String, _ body: String) {
        let attachment = XCTAttachment(data: Data(body.utf8), uniformTypeIdentifier: "public.plain-text")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func shotSpringboard(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForHomeLabel(_ app: XCUIApplication, containing needle: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let query = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", needle))
        while Date() < deadline {
            if query.firstMatch.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        return query.firstMatch.exists
    }

    /// Xcode 26 times out when the test runner launches the same app a second time
    /// through the debugger. Opening the home-screen icon is a real restart.
    private func relaunchFromHomeScreen() {
        app.terminate()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        XCTAssertTrue(springboard.icons["宝宝小记"].waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        home.name = "08-home-screen"
        home.lifetime = .keepAlways
        add(home)
        let appIcon = homeAppIcon(springboard)
        XCTAssertNotNil(appIcon, "The app icon was not separate from the widget.")
        appIcon?.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        if !(button.exists && button.isHittable) {
            for _ in 0..<6 {
                app.swipeDown()
                if button.exists && button.isHittable { break }
            }
        }
        var swipes = 0
        while swipes < 6 && !(button.exists && button.isHittable) {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(button.waitForExistence(timeout: 4), identifier)
        button.tap()
    }

    private func logFormula(millilitres: String) {
        app.buttons["add-formula"].tap()
        XCTAssertFalse(app.staticTexts["备注"].exists)
        let amount = app.textFields["bottle-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(amount.frame.height, 44)
        let now = app.buttons["time-now"]
        revealFormControl(now)
        XCTAssertTrue(now.waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(now.frame.height, 44)
        XCTAssertTrue(app.descendants(matching: .any)["time-heading"].waitForExistence(timeout: 4))
        let wheel = app.descendants(matching: .any)["time-wheel"]
        revealFormControl(wheel)
        XCTAssertTrue(wheel.waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(wheel.frame.height, 120, "time control is still the compact picker")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "time-heading").count, 1)
        XCTAssertTrue(app.staticTexts["成品奶量"].exists)
        amount.tap()
        amount.typeText(millilitres)
        let save = tapSave("formula")
        XCTAssertTrue(save.waitForNonExistence(timeout: 4), "formula form stayed open")
        let card = element("summary-formula")
        let showed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", millilitres), object: card)
        XCTAssertEqual(XCTWaiter().wait(for: [showed], timeout: 4), .completed, "formula card stayed \(card.label) \(saveTrace)")
    }

    private func saveCurrentForm(_ addIdentifier: String) {
        tap(addIdentifier)
        let save = tapSave(addIdentifier)
        XCTAssertTrue(save.waitForNonExistence(timeout: 4), "\(addIdentifier) form stayed open, so it was not saved")
    }

    private func loggedAge(_ label: String) -> Bool {
        label.contains("刚刚") || label.contains("分钟前") || label.contains("小时")
    }

    /// Taps start only after the field value is the full name and the button is enabled.
    /// A tap while the name is still arriving is ignored, and the welcome screen stays up.
    private func createBabyNamed(_ babyName: String) {
        let field = app.textFields["baby-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        if (field.value as? String) != babyName {
            field.tap()
            field.typeText(babyName)
        }
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", babyName), object: field)
        XCTAssertEqual(
            XCTWaiter().wait(for: [committed], timeout: 8),
            .completed,
            "baby name stayed \(field.value ?? "nil")"
        )
        let key = app.buttons["start-tracking-key"]
        let start = app.buttons["start-tracking"]
        let target = key.exists && key.isHittable ? key : start
        XCTAssertTrue(target.isEnabled, "start stayed disabled after the name was \(field.value ?? "nil")")
        target.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 4), "welcome stayed open after start")
    }

    /// Taps the save control that is actually hittable. Does not dismiss the keyboard first.
    @discardableResult
    private func tapSave(_ note: String) -> XCUIElement {
        let target = app.buttons["save-entry"]
        XCTAssertTrue(target.waitForExistence(timeout: 4), note)
        XCTAssertTrue(target.isHittable, "\(note) save is not hittable")
        XCTAssertGreaterThanOrEqual(target.frame.height, 44, note)
        target.tap()
        return target
    }

    private var saveTrace: String {
        let probe = app.descendants(matching: .any)["save-trace"]
        return probe.exists ? probe.label : "no-trace"
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Sleep is the last home card. A list drops that row from the accessibility tree while it is off screen.
    /// Scroll it back, then the caller checks the saved text. The card stays in the layout.
    private func requireSleepCard() -> XCUIElement {
        XCTAssertTrue(reveal("summary-sleep", swiping: .up), "summary-sleep was not in the Today list")
        let sleep = element("summary-sleep")
        XCTAssertTrue(sleep.waitForExistence(timeout: 4))
        return sleep
    }

    /// The dock draws the four tabs. A hidden system tab bar is only a fallback.
    private func tab(_ title: String) -> XCUIElement {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", title))
        if let hit = buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            return hit
        }
        if buttons.firstMatch.exists { return buttons.firstMatch }
        return app.tabBars.buttons[title]
    }

    /// Premise: the minute must be stored and the sheet must close. The card then shows that duration.
    /// A label that still says 还没有 means the save did not happen, not a missing accessibility string.
    private func logNursing() {
        tap("add-breast")
        let minutes = app.textFields["breast-left-minutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        minutes.tap()
        minutes.typeText("1")
        let shown = minutes.value as? String ?? ""
        XCTAssertTrue(shown.contains("1"), "typed minute was not in the field: \(shown)")
        let save = tapSave("nursing")
        XCTAssertTrue(save.waitForNonExistence(timeout: 4), "nursing form stayed open, so the minute was not saved")
        XCTAssertTrue(minutes.waitForNonExistence(timeout: 2), "nursing minute field still open")
    }

    private func openWidgetPreview() {
        let title = tab("设置").exists ? "设置" : "Settings"
        returnToSettingsHub(tabTitle: title)
        let widgets = app.descendants(matching: .any)["settings-module-widgets"]
        XCTAssertTrue(widgets.waitForExistence(timeout: 4), "settings-module-widgets")
        widgets.tap()
        let button = app.buttons["show-widget-preview"]
        for _ in 0..<5 where !button.exists { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.tap()
    }

    /// Settings tabs keep the last page. Nested widget, baby, and provider screens hide the hub.
    private func returnToSettingsHub(tabTitle: String) {
        tab(tabTitle).tap()
        let hub = app.descendants(matching: .any)["settings-module-records"]
        for _ in 0..<5 {
            if hub.exists, hub.isHittable { return }
            if app.buttons["close-widget-preview"].exists {
                app.buttons["close-widget-preview"].tap()
                continue
            }
            if app.navigationBars.buttons["取消"].exists {
                app.navigationBars.buttons["取消"].tap()
                continue
            }
            if !hub.exists {
                let back = app.navigationBars.buttons.element(boundBy: 0)
                if back.exists, back.isHittable {
                    back.tap()
                    continue
                }
            }
            app.swipeDown()
        }
    }

    private func closeWidgetPreview() {
        let close = app.buttons["close-widget-preview"]
        XCTAssertTrue(close.waitForExistence(timeout: 4))
        let visible = app.buttons.allElementsBoundByIndex.first { $0.identifier == "close-widget-preview" && $0.isHittable } ?? close
        visible.tap()
        if close.exists {
            _ = close.waitForNonExistence(timeout: 4)
        }
        if close.exists, close.isHittable {
            close.tap()
        }
        XCTAssertTrue(close.waitForNonExistence(timeout: 8), "widget preview stayed open")
        let today = app.buttons["dock-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 4), "today dock did not return after the widget preview closed")
        today.tap()
        let formula = app.buttons["add-formula"]
        if !formula.waitForExistence(timeout: 2) {
            for _ in 0..<6 where !formula.exists {
                app.swipeDown()
            }
        }
        XCTAssertTrue(formula.waitForExistence(timeout: 4), "today did not appear after the dock tap")
    }

    func testBottomOfTodayStaysInteractive() throws {
        app.launchArguments += ["-lbl-ui-reset"]
        app.launch()
        createBabyNamed("Beibei")
        XCTAssertTrue(app.buttons["add-formula"].waitForExistence(timeout: 8))

        for _ in 0..<4 { app.swipeUp() }
        let solids = app.buttons["add-solids"]
        XCTAssertTrue(solids.waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(solids.frame.height, 44)
        XCTAssertFalse(solids.label.contains("还没有"))
        solids.tap()
        let save = app.buttons["save-entry"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(solids.waitForExistence(timeout: 4))

        app.swipeDown()
        XCTAssertTrue(app.buttons["add-formula"].waitForExistence(timeout: 4))
        tab("历史").tap()
        XCTAssertTrue(app.navigationBars["历史"].waitForExistence(timeout: 4))
        tab("今天").tap()
        for _ in 0..<4 { app.swipeUp() }
        let growth = app.buttons["add-growth"]
        XCTAssertTrue(growth.waitForExistence(timeout: 6))
        growth.tap()
        XCTAssertTrue(app.buttons["save-entry"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["取消"].tap()

        let voice = app.buttons["voice-log"]
        XCTAssertTrue(voice.waitForExistence(timeout: 4))
        voice.tap()
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["voice-start"].exists)
        tab("今天").tap()
        XCTAssertTrue(reveal("add-formula", swiping: .down))
    }

    func testVoiceButtonDoesNotAskForTheMicrophoneWhenAIIsOff() throws {
        app.launchArguments += ["-lbl-ui-reset"]
        app.launch()
        createBabyNamed("Beibei")

        let voice = app.buttons["voice-log"]
        XCTAssertTrue(voice.waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(voice.frame.height, 44)
        voice.tap()
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["voice-start"].exists)
        XCTAssertFalse(app.buttons["ai-verify"].exists)
        app.buttons["add-provider"].tap()
        app.buttons["provider-deepseek"].tap()
        let keyField = app.secureTextFields["ai-key-field"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 4))
        let model = app.descendants(matching: .any)["ai-model"]
        XCTAssertTrue(model.waitForExistence(timeout: 4))
        XCTAssertTrue(model.label.contains("Flash"))
        choosePicker("ai-model", option: "V4 Pro")
        waitUntil(model, contains: "V4 Pro")
        app.navigationBars.buttons["取消"].tap()
        app.buttons["add-provider"].tap()
        app.buttons["provider-kimiAI"].tap()
        XCTAssertTrue(model.waitForExistence(timeout: 4))
        waitUntil(model, contains: "K3.1 Pro")
        choosePicker("ai-model", option: "K3", exact: true)
        waitUntil(model, contains: "K3", excluding: "K3.1")
        XCTAssertTrue(tab("历史").exists)
        XCTAssertTrue(tab("趋势").exists)
        XCTAssertTrue(tab("设置").exists)
    }

    func testChatComposerStaysAboveTheKeyboard() {
        app.launchArguments += ["-lbl-ui-reset", "-lbl-show-chat"]
        app.launch()
        createBabyNamed("Beibei")
        let field = app.descendants(matching: .any)["ai-chat-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "chat composer did not open")
        let bar = app.descendants(matching: .any)["composer-bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 4))
        XCTAssertGreaterThan(bar.frame.width, app.frame.width * 0.8)
        XCTAssertGreaterThanOrEqual(bar.frame.height, 52)
        shot("review-chat-composer")
        field.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 6))
        XCTAssertLessThanOrEqual(bar.frame.maxY, keyboard.frame.minY + 8)
        shot("review-chat-keyboard")
    }

    /// Opens the screens this build can reach in the simulator and keeps a screenshot of each.
    /// A missing control fails the test. Screens that need a microphone, a real model, or SpringBoard are not opened.
    func testReviewSurfacesLeaveScreenshots() throws {
        app.launchArguments += ["-lbl-ui-reset"]
        app.launch()
        let name = app.textFields["baby-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        shot("review-01-new-baby")
        createBabyNamed("Beibei")
        XCTAssertTrue(app.buttons["add-formula"].waitForExistence(timeout: 8))
        let icon = app.descendants(matching: .any)["icon-formula"]
        XCTAssertTrue(icon.waitForExistence(timeout: 4))
        XCTAssertLessThanOrEqual(icon.frame.width, 48)
        XCTAssertLessThanOrEqual(icon.frame.height, 48)
        shot("review-02-today")
        app.buttons["home-cards-config"].tap()
        let sleep = app.switches["home-card-sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 4))
        shot("review-02b-home-cards")
        setSwitch(sleep, on: false)
        app.buttons["home-cards-done"].tap()
        XCTAssertTrue(app.buttons["home-cards-done"].waitForNonExistence(timeout: 4))
        XCTAssertFalse(app.buttons["summary-sleep"].exists)
        app.buttons["home-cards-config"].tap()
        XCTAssertTrue(sleep.waitForExistence(timeout: 4))
        XCTAssertEqual(sleep.value as? String, "0")
        setSwitch(sleep, on: true)
        app.buttons["home-cards-done"].tap()
        XCTAssertTrue(app.buttons["home-cards-done"].waitForNonExistence(timeout: 4))
        XCTAssertTrue(reveal("summary-sleep", swiping: .up))

        openForm("add-formula", shotName: "review-03-formula") {
            XCTAssertTrue(self.app.textFields["bottle-amount"].waitForExistence(timeout: 3))
            let wheel = self.app.descendants(matching: .any)["time-wheel"]
            self.revealFormControl(wheel)
            XCTAssertTrue(wheel.waitForExistence(timeout: 4))
            XCTAssertGreaterThanOrEqual(wheel.frame.height, 120)
            XCTAssertEqual(self.app.descendants(matching: .any).matching(identifier: "time-heading").count, 1)
        }
        for pair in [
            ("add-breast", "review-04-breast"),
            ("add-sleep", "review-05-sleep"),
            ("add-wet", "review-06-wet"),
            ("add-dirty", "review-07-dirty"),
            ("add-diaper-change", "review-08-change"),
            ("add-solids", "review-09-solids"),
            ("add-pump", "review-10-pump"),
            ("add-growth", "review-11-growth"),
            ("add-medicine", "review-12-medicine"),
        ] {
            openForm(pair.0, shotName: pair.1, check: nil)
        }

        for _ in 0..<4 { app.swipeDown() }
        logFormula(millilitres: "120")
        shot("review-13-today-after-formula")
        app.buttons["summary-formula"].tap()
        XCTAssertTrue(element("timeline-total").waitForExistence(timeout: 5))
        shot("review-14-formula-timeline")
        // The back button uses the previous title, which is the baby's name, not the tab title.
        let back = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()

        tab("历史").tap()
        XCTAssertTrue(app.navigationBars["历史"].waitForExistence(timeout: 4))
        shot("review-15-history")
        app.buttons["列表"].tap()
        let entry = app.buttons["history-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        entry.tap()
        XCTAssertTrue(app.buttons["save-entry"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["bottle-amount"].exists)
        shot("review-16-edit-formula")
        app.navigationBars.buttons["取消"].tap()

        tab("趋势").tap()
        XCTAssertTrue(app.navigationBars["趋势"].waitForExistence(timeout: 4))
        shot("review-17-trends")

        tab("设置").tap()
        for _ in 0..<4 { app.swipeDown() }
        shot("review-18-settings")
        let records = app.descendants(matching: .any)["settings-module-records"]
        if records.waitForExistence(timeout: 4) { records.tap() }
        let baby = app.buttons["settings-baby"]
        XCTAssertTrue(baby.waitForExistence(timeout: 4))
        baby.tap()
        XCTAssertTrue(app.textFields["baby-name"].waitForExistence(timeout: 4))
        shot("review-19-baby-form")
        app.navigationBars.buttons["取消"].tap()

        openLabeled("settings-home-cards")
        shot("review-21-home-cards")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openLabeled("settings-reminders")
        shot("review-20-reminders")
        popNavigation()
        openLabeled("settings-assistant")
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 4))
        app.buttons["add-provider"].tap()
        app.buttons["provider-deepseek"].tap()
        XCTAssertTrue(app.secureTextFields["ai-key-field"].waitForExistence(timeout: 4))
        shot("review-22-ai-settings")
        if app.navigationBars.buttons["取消"].exists {
            app.navigationBars.buttons["取消"].tap()
        }
        returnToSettingsHub(tabTitle: "设置")

        let dataModule = app.descendants(matching: .any)["settings-module-data"]
        XCTAssertTrue(dataModule.waitForExistence(timeout: 4), "settings-module-data")
        dataModule.tap()
        let sync = app.staticTexts["iCloud 同步"]
        var syncSwipes = 0
        while syncSwipes < 8 && !sync.exists {
            app.swipeUp()
            syncSwipes += 1
        }
        XCTAssertTrue(sync.waitForExistence(timeout: 4))
        let importer = app.descendants(matching: .any)["import-ordinary"]
        XCTAssertTrue(importer.waitForExistence(timeout: 4), "import-ordinary")
        shot("review-23-sync-import")

        openWidgetPreview()
        assertWidgetSample("widget-sample-small-1", cards: ["breast"])
        assertWidgetSample("widget-sample-small-2", cards: ["breast", "formula"])
        assertWidgetSample("widget-sample-small-6", cards: ["breast", "formula", "wet", "dirty", "diaperChange", "sleep"])
        assertWidgetSample("widget-sample-medium-4", cards: ["breast", "formula", "wet", "dirty"])
        assertWidgetSample("widget-sample-medium-6", cards: ["breast", "formula", "wet", "dirty", "diaperChange", "sleep"])
        assertWidgetSample("widget-sample-large-6", cards: ["breast", "formula", "wet", "dirty", "diaperChange", "sleep"])
        assertWidgetSample("widget-sample-dark-6", cards: ["breast", "formula", "wet", "dirty", "diaperChange", "sleep"])
        shot("review-24-widget-samples")
        closeWidgetPreview()
        requireAppearance("dark", settingsTab: "设置", homeTab: "今天", name: "review-25-today-dark")
    }

    /// The switch sits beside another button. Tap the knob, then wait until the value actually changes.
    private func setSwitch(_ control: XCUIElement, on: Bool) {
        let wanted = on ? "1" : "0"
        if control.value as? String == wanted { return }
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        var ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", wanted), object: control)
        if XCTWaiter().wait(for: [ready], timeout: 2) == .completed { return }
        control.tap()
        ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", wanted), object: control)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 4), .completed, "switch stayed \(control.value ?? "nil")")
    }

    /// A tall form keeps the wheel below the first screen. Scroll until it is in the tree.
    private func revealFormControl(_ element: XCUIElement) {
        var swipes = 0
        while swipes < 4 && !element.exists {
            app.swipeUp()
            swipes += 1
        }
    }

    private func openForm(_ identifier: String, shotName: String, check: (() -> Void)?) {
        tap(identifier)
        let save = app.buttons["save-entry"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), identifier)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44, identifier)
        check?()
        shot(shotName)
        app.navigationBars.buttons["取消"].tap()
        // The list unloads rows that scrolled away, so return to the top before looking for the first card.
        XCTAssertTrue(reveal("add-formula", swiping: .down), identifier)
    }

    /// Settings rows are links, and a lazy list drops the ones that scrolled away.
    private func openLabeled(_ label: String) {
        for _ in 0..<6 { app.swipeDown() }
        let element = app.descendants(matching: .any)[label]
        var swipes = 0
        while swipes < 8 && !(element.exists && element.isHittable) {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 4), label)
        element.tap()
    }

    private func popNavigation() {
        let back = app.navigationBars.buttons["BackButton"]
        if back.waitForExistence(timeout: 2) {
            back.tap()
        } else if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        _ = app.navigationBars["设置"].waitForExistence(timeout: 4)
    }

    private enum SwipeDirection {
        case up, down
    }

    /// Lazy lists omit off-screen buttons. Swipe until the identifier is back in the tree.
    private func reveal(_ identifier: String, swiping direction: SwipeDirection) -> Bool {
        let element = app.buttons[identifier]
        if element.waitForExistence(timeout: 2) { return true }
        for _ in 0..<6 {
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
            if element.exists { return true }
        }
        return element.waitForExistence(timeout: 2)
    }

    private func assertWidgetSample(_ identifier: String, cards: [String]) {
        let sample = bringOnScreen(identifier)
        shot(identifier)
        let labels = sample.descendants(matching: .any).allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertFalse(labels.contains("贝贝"), identifier)
        XCTAssertFalse(labels.contains("Beibei"), identifier)
        for card in cards {
            let item = sample.descendants(matching: .any)["widget-item-\(card)"]
            XCTAssertTrue(item.waitForExistence(timeout: 2), "\(identifier) \(card)")
            let visible = item.frame.intersection(sample.frame)
            XCTAssertGreaterThanOrEqual(visible.height, 16, "\(identifier) \(card)")
            XCTAssertGreaterThanOrEqual(visible.width, 40, "\(identifier) \(card)")
        }
    }

    private func bringOnScreen(_ identifier: String) -> XCUIElement {
        let element = self.element(identifier)
        for _ in 0..<12 {
            if element.exists, element.frame.height > 40,
               element.frame.minY > 40, element.frame.maxY < app.frame.maxY - 8 {
                return element
            }
            if element.exists, element.frame.minY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2), identifier)
        return element
    }

    private func waitUntil(_ element: XCUIElement, contains text: String, excluding: String? = nil) {
        let predicate = excluding == nil
            ? NSPredicate(format: "label CONTAINS %@", text)
            : NSPredicate(format: "label CONTAINS %@ AND NOT label CONTAINS %@", text, excluding!)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 4), .completed)
    }

    private func choosePicker(_ identifier: String, option: String, exact: Bool = false) {
        let control = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 4))
        control.tap()
        let query = exact
            ? NSPredicate(format: "label == %@", option)
            : NSPredicate(format: "label == %@ OR label BEGINSWITH %@", option, option)
        let choice = app.descendants(matching: .any).matching(query).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 4))
        choice.tap()
        if app.navigationBars[option].exists || app.navigationBars["模型"].exists || app.navigationBars["供应商"].exists {
            let back = app.navigationBars.buttons["AI 助手"]
            if back.exists { back.tap() }
        }
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
