import XCTest

final class PoochiUITests: XCTestCase {
    func testSampleDashboardVideosAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--sample"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Poochi & Friends · Sample"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1,280"].exists)
        attach(app, name: "Sample dashboard")
        app.descendants(matching: .any).matching(identifier: "nav.videos").firstMatch.click()
        XCTAssertTrue(app.staticTexts["Every post has a story"].waitForExistence(timeout: 5))
        let search = app.textFields["Search video titles"]
        search.click(); search.typeText("does-not-exist")
        XCTAssertTrue(app.staticTexts["No videos match. Check your filters and TikTok video permission."].waitForExistence(timeout: 3))
        search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Poochi discovers the camera"].waitForExistence(timeout: 3))
        attach(app, name: "Sample videos")
        app.buttons["Settings"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["TikTok connection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields.count > 0)
        attach(app, name: "Connection settings")
        app.terminate()
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
