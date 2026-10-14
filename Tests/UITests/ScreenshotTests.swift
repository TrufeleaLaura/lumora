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

    private func open(_ app: XCUIApplication, tool: String) {
        let button = app.buttons["tool.\(tool)"]
        guard button.waitForExistence(timeout: 5) else { return }
        // Tools live in a scrolling bar: swipe until the button is on screen.
        let screen = app.windows.firstMatch.frame
        let bar = app.scrollViews.containing(.button, identifier: "tool.looks").firstMatch
        var attempts = 0
        while attempts < 6 {
            let frame = button.frame
            if frame.minX >= screen.minX && frame.maxX <= screen.maxX && !frame.isEmpty { break }
            if frame.maxX > screen.maxX { bar.swipeLeft() } else { bar.swipeRight() }
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

        let tools = ["looks", "enhance", "adjust", "masks", "retouch", "styles", "overlays", "text", "face", "body", "reshape", "crop"]
        for (index, tool) in tools.enumerated() {
            open(app, tool: tool)
            save(String(format: "%02d-%@", index + 1, tool))
        }

        // A few deeper screens.
        open(app, tool: "masks")
        if button(app, containing: "Subject").waitForExistence(timeout: 3) {
            button(app, containing: "Subject").tap()
            sleep(6)
            save("20-masks-subject")
        }
        open(app, tool: "overlays")
        if app.buttons["Frame"].waitForExistence(timeout: 3) {
            app.buttons["Frame"].tap()
            sleep(1)
            if button(app, containing: "Instant").exists { button(app, containing: "Instant").tap() }
            sleep(3)
            save("21-overlays-frame")
            let canvas = app.descendants(matching: .any)["canvas"]
            let info = "canvas: \(canvas.value as? String ?? "?") frame: \(canvas.frame)"
            print(info)
            if let directory = outputDirectory {
                try? info.write(to: directory.appendingPathComponent("canvas-info.txt"), atomically: true, encoding: .utf8)
            }
        }
        open(app, tool: "styles")
        sleep(1)
        save("22-styles")

        app.buttons["Export"].tap()
        sleep(2)
        save("23-export")
    }

    func testLibraryAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()
        sleep(3)
        save("30-library")
        if app.buttons["Settings"].waitForExistence(timeout: 5) {
            app.buttons["Settings"].tap()
            sleep(2)
            save("31-settings")
            if button(app, containing: "welcome tour").waitForExistence(timeout: 3) {
                button(app, containing: "welcome tour").tap()
                sleep(3)
                save("32-onboarding")
            }
        }
    }
}
