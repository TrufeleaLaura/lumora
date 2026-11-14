import XCTest

/// Walks through the editor with the bundled sample photo and saves a screenshot of every
/// tool (written next to the render tests' contact sheets on CI).
final class ScreenshotTests: XCTestCase {
    private var outputDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["LUMORA_TEST_OUTPUT"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path).appendingPathComponent("ui", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func save(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = outputDirectory {
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// Opens a category, then one of its tools (swiping the tool tabs until it is on screen).
    private func open(_ app: XCUIApplication, category: String, tool: String) {
        let categoryButton = app.buttons["cat.\(category)"]
        guard categoryButton.waitForExistence(timeout: 5) else { return }
        categoryButton.tap()
        let button = app.buttons["tool.\(tool)"]
        guard button.waitForExistence(timeout: 5) else { return }
        let screen = app.windows.firstMatch.frame
        let tabs = app.scrollViews.containing(.button, identifier: "tool.\(tool)").firstMatch
        var attempts = 0
        while attempts < 6 {
            let frame = button.frame
            if frame.minX >= screen.minX && frame.maxX <= screen.maxX && !frame.isEmpty { break }
            if frame.maxX > screen.maxX { tabs.swipeLeft() } else { tabs.swipeRight() }
            attempts += 1
        }
        button.tap()
        sleep(3)
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func testToolScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-skipOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 90), "the editor opens with the sample photo")
        sleep(3)
        save("00-editor")

        let map: [(String, [String])] = [
            ("looks", ["presets", "auto"]),
            ("adjust", ["light", "color", "curve", "grading", "detail", "masks", "crop"]),
            ("portrait", ["skin", "features", "makeup", "hair", "body", "reshape"]),
            ("retouch", ["remove", "heal", "clone", "sky", "background"]),
            ("create", ["effects", "lightAndDust", "frames", "text", "stickers"]),
        ]
        var index = 1
        for (category, tools) in map {
            for (position, tool) in tools.enumerated() {
                open(app, category: category, tool: tool)
                save(String(format: "%02d-%@-%@", index, category, tool))
                index += 1
                // Each category's first-time tip shows once; dismiss it after its first screenshot.
                if position == 0, app.buttons["tip.dismiss"].exists {
                    app.buttons["tip.dismiss"].tap()
                    sleep(1)
                }
            }
        }

        // A few deeper screens.
        open(app, category: "adjust", tool: "masks")
        if button(app, containing: "Subject").waitForExistence(timeout: 3) {
            button(app, containing: "Subject").tap()
            sleep(6)
            save("40-masks-subject")
        }
        open(app, category: "create", tool: "frames")
        if button(app, containing: "Instant").waitForExistence(timeout: 3) {
            button(app, containing: "Instant").tap()
            sleep(3)
            save("41-frames-instant")
            let canvas = app.descendants(matching: .any)["canvas"]
            let info = "canvas: \(canvas.value as? String ?? "?") frame: \(canvas.frame)"
            print(info)
            if let directory = outputDirectory {
                try? info.write(to: directory.appendingPathComponent("canvas-info.txt"), atomically: true, encoding: .utf8)
            }
        }

        // Find a tool, a goal's recipe, and the guided steps.
        if app.buttons["Find a tool"].waitForExistence(timeout: 3) {
            app.buttons["Find a tool"].tap()
            sleep(2)
            save("42-find-a-tool")
            if app.buttons["findgoal.portrait"].waitForExistence(timeout: 3) {
                app.buttons["findgoal.portrait"].tap()
                sleep(2)
                save("43-recipe")
                if app.buttons["Start"].waitForExistence(timeout: 3) {
                    app.buttons["Start"].tap()
                    sleep(3)
                    save("44-guided")
                }
            }
        }
        if app.buttons["Find a tool"].waitForExistence(timeout: 3) {
            app.buttons["Find a tool"].tap()
            sleep(2)
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) {
                search.tap()
                search.typeText("teeth")
                sleep(2)
                save("45-search")
            }
            if app.buttons["Close"].exists { app.buttons["Close"].tap() }
            sleep(1)
        }

        if app.buttons["Export"].waitForExistence(timeout: 3) {
            app.buttons["Export"].tap()
            sleep(2)
            save("46-export")
        }
    }

    func testLibraryAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()
        sleep(3)
        save("30-library")
        let goal = app.buttons["goal.portrait"]
        if goal.waitForExistence(timeout: 5) {
            goal.tap()
            sleep(2)
            save("31-home-recipe")
            app.swipeDown(velocity: .fast)
            sleep(2)
        }
        if app.buttons["Settings"].waitForExistence(timeout: 5) {
            app.buttons["Settings"].tap()
            sleep(2)
            save("32-settings")
            if button(app, containing: "welcome tour").waitForExistence(timeout: 3) {
                button(app, containing: "welcome tour").tap()
                sleep(3)
                save("33-onboarding")
            }
        }
    }
}
