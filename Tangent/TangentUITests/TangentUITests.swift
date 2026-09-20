//
//  TangentUITests.swift
//  TangentUITests
//
//  Created by Sierra Bonilla on 18/09/2026.
//

import XCTest

final class TangentUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMultipleRecordingsAndCalendarPopover() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding", "--multiple-recordings"]
        app.launch()
        app.buttons["complete-onboarding"].tap()
        let morning = app.buttons["diary-entry-11111111-1111-1111-1111-111111111111"]
        let afternoon = app.buttons["diary-entry-22222222-2222-2222-2222-222222222222"]
        XCTAssertTrue(morning.waitForExistence(timeout: 3))
        XCTAssertTrue(afternoon.exists)
        XCTAssertLessThan(morning.frame.minY, afternoon.frame.minY)
        let diary = XCTAttachment(screenshot: app.screenshot())
        diary.name = "Two recordings for today"
        diary.lifetime = .keepAlways
        add(diary)
        morning.tap()
        XCTAssertTrue(app.staticTexts["recording-start-time"].waitForExistence(timeout: 3))
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Recording start time"
        detail.lifetime = .keepAlways
        add(detail)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["add-record"].tap()
        app.buttons["Record for today"].tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 3))
        app.buttons["diary-home-logo"].tap()
        app.buttons["add-record"].tap()
        app.datePickers.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let calendarPicker = app.datePickers.containing(.button, identifier: "DatePicker.PreviousMonth").firstMatch
        XCTAssertTrue(calendarPicker.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["record-selected-day"].exists)
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "Choose a past day"
        picker.lifetime = .keepAlways
        add(picker)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let day = String(Calendar.current.component(.day, from: yesterday))
        calendarPicker.buttons.containing(.staticText, identifier: day).firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start recording for")).firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testPlusOpensCalendarDirectlyBeforeTodaysFirstTangent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding", "--demo-data"]
        app.launch()
        app.buttons["complete-onboarding"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 3))
        app.datePickers.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let calendarPicker = app.datePickers.containing(.button, identifier: "DatePicker.PreviousMonth").firstMatch
        XCTAssertTrue(calendarPicker.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native calendar above plus at end of long diary"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.buttons["Record for today"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        XCTAssertTrue(calendarPicker.waitForNonExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Record today’s Tangent")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDiaryNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding"]
        app.launch()
        app.buttons["complete-onboarding"].tap()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 2)
        )

        app.navigationBars["Settings"].buttons.firstMatch.tap()

        let recordTodayButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Record today’s Tangent")).firstMatch
        XCTAssertTrue(recordTodayButton.waitForExistence(timeout: 2))
        recordTodayButton.tap()
        XCTAssertTrue(
            app.buttons["Start recording"].waitForExistence(timeout: 2)
        )

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(
            app.navigationBars["Insights"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testGeneralProfileAndModelChoices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding"]
        app.launch()
        app.buttons["complete-onboarding"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["profile-name"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Your focus")).firstMatch.exists)
        let interests = app.descendants(matching: .any).matching(identifier: "profile-interests").firstMatch
        XCTAssertTrue(interests.exists)
        interests.tap()
        interests.typeText("Creative writing")
        XCTAssertFalse(app.buttons["save-profile"].exists)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(interests.waitForExistence(timeout: 3))
        XCTAssertEqual(interests.value as? String, "Creative writing")

        let ai = app.switches["ai-enabled"]
        for _ in 0..<5 where !ai.isHittable { app.swipeUp() }
        ai.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let gemma = app.buttons["model-gemma3n-e2b-it-lm-4bit"]
        XCTAssertFalse(app.buttons["model-qwen2.5-0.5b-instruct-4bit"].exists)
        // Form can report a partially clipped row as hittable. Reveal the whole row.
        for _ in 0..<5 where !gemma.isHittable || gemma.frame.maxY > app.frame.maxY - 80 {
            app.swipeUp()
        }
        XCTAssertTrue(gemma.isHittable)
        gemma.tap()
        XCTAssertEqual(gemma.value as? String, "Selected")
        // Choosing a model is a preference; it must not start downloading weights.
        XCTAssertFalse(app.buttons["Cancel"].exists)
    }

    @MainActor
    func testOnboardingCanSkipModelSetupAndScrollThroughModels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding"]
        app.launch()
        let ai = app.switches["ai-enabled"]
        XCTAssertTrue(ai.waitForExistence(timeout: 5))
        ai.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["complete-onboarding"].isEnabled)
        let lastModel = app.buttons["model-medgemma-1.5-4b-it-4bit"]
        for _ in 0..<6 where !lastModel.isHittable { app.swipeUp() }
        XCTAssertTrue(lastModel.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Onboarding model choices scrolled"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["continue-without-ai"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
        app.buttons["Settings"].tap()
        let settingsAI = app.switches["ai-enabled"]
        for _ in 0..<5 where !settingsAI.isHittable { app.swipeUp() }
        XCTAssertEqual(settingsAI.value as? String, "0")
        settingsAI.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["AI summaries will stay off until a model is downloaded"].exists)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        app.buttons["Settings"].tap()
        for _ in 0..<5 where !settingsAI.isHittable { app.swipeUp() }
        XCTAssertEqual(settingsAI.value as? String, "0")
    }

    @MainActor
    func testFirstLaunchWithAIOptional() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["complete-onboarding"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["ai-enabled"].value as? String, "0")
        XCTAssertEqual(app.switches["ai-enabled"].label, "AI summaries")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Onboarding"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let onboardingAI = app.switches["ai-enabled"]
        let concernsField = app.descendants(matching: .any).matching(identifier: "profile-concerns").firstMatch
        XCTAssertGreaterThan(onboardingAI.frame.minY, concernsField.frame.maxY)
        let nameBeforeExpansion = app.textFields["profile-name"].frame
        onboardingAI.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["ai-setup-required"].exists)
        XCTAssertFalse(app.buttons["complete-onboarding"].isEnabled)
        XCTAssertTrue(app.buttons["continue-without-ai"].exists)
        XCTAssertEqual(app.textFields["profile-name"].frame.minY, nameBeforeExpansion.minY, accuracy: 2)
        let enabledScreenshot = XCTAttachment(screenshot: app.screenshot())
        enabledScreenshot.name = "Onboarding with AI summaries on"
        enabledScreenshot.lifetime = .keepAlways
        add(enabledScreenshot)
        onboardingAI.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let name = app.textFields["profile-name"]
        name.tap()
        name.typeText("Alex")
        let interests = app.descendants(matching: .any).matching(identifier: "profile-interests").firstMatch
        for _ in 0..<5 where !interests.exists || !interests.isHittable { app.swipeUp() }
        interests.tap()
        app.typeText("Drawing")
        let concerns = app.descendants(matching: .any).matching(identifier: "profile-concerns").firstMatch
        for _ in 0..<5 where !concerns.exists || !concerns.isHittable { app.swipeUp() }
        concerns.tap()
        app.typeText("Finding time")
        app.buttons["complete-onboarding"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
        app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["profile-name"].value as? String, "Alex")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "profile-interests").firstMatch.exists)
        let ai = app.switches["ai-enabled"]
        for _ in 0..<5 where !ai.isHittable { app.swipeUp() }
        XCTAssertEqual(ai.value as? String, "0")
        XCTAssertFalse(app.buttons["model-qwen3-0.6b-4bit"].exists)
        ai.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["model-qwen3-0.6b-4bit"].waitForExistence(timeout: 2))
        ai.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["model-qwen3-0.6b-4bit"].exists)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        app.tabBars.buttons["Insights"].tap()
        XCTAssertFalse(app.buttons["generate-insight"].isEnabled)
        XCTAssertTrue(app.buttons["Download model in Settings for this functionality."].exists)
        app.buttons["Download model in Settings for this functionality."].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        let insightsScreenshot = XCTAttachment(screenshot: app.screenshot())
        insightsScreenshot.name = "Insights with AI off"
        insightsScreenshot.lifetime = .keepAlways
        add(insightsScreenshot)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["complete-onboarding"].exists)
        app.buttons["Settings"].tap()
        XCTAssertEqual(app.textFields["profile-name"].value as? String, "Alex")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "profile-interests").firstMatch.value as? String, "Drawing")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "profile-concerns").firstMatch.value as? String, "Finding time")
    }

    @MainActor
    func testDiaryUsesTranscriptWhenAIIsOff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding", "--demo-data"]
        app.launch()
        app.buttons["complete-onboarding"].tap()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hi. I wanted to check in about today.")).firstMatch
        for _ in 0..<5 where !entry.isHittable { app.swipeDown() }
        XCTAssertTrue(entry.exists)
        XCTAssertTrue(entry.label.hasSuffix("..."))
        entry.tap()
        XCTAssertTrue(app.staticTexts["Transcript"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Summary"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Daily diary with AI off"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
