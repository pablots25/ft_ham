//
//  BehaviorSettingsUITests.swift
//  ft8_hamUITests
//
//  Created by GitHub Copilot on 04/04/26.
//

import XCTest

// MARK: - BehaviorSettings UI Tests

/// UI tests that navigate to the Behavior settings screen and verify that
/// each toggle control is present and responds to user interaction.
///
/// These tests use the accessibility identifiers added to BehaviorSettingsView
/// (prefixed `toggle_` and `field_`) as well as standard accessibility labels
/// set on the Toggle controls via ToggleRow.
final class BehaviorSettingsUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Scroll Helper

    /// Scrolls until `element` is hittable, or gives up after `maxSwipes` attempts.
    /// Waits for any in-flight navigation animation to settle before starting to swipe.
    @MainActor
    private func scrollToVisible(_ element: XCUIElement, maxSwipes: Int = 5) {
        guard !element.isHittable else { return }
        // Let the navigation slide-in animation finish before touching the scroll view.
        let hittablePredicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittablePredicate, object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 1.5) == .completed { return }
        // Prefer a table (SwiftUI List), fall back to any scroll view.
        let list = app.tables.firstMatch
        let scrollView = list.exists ? list : app.scrollViews.firstMatch
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            scrollView.swipeUp()
            attempts += 1
        }
    }

    // MARK: - Navigation Helper

    /// Navigates from the app's root to the Behavior settings screen.
    @MainActor
    private func navigateToBehaviorSettings() {
        // The tab bar item for Settings/Configuration is labelled "Settings"
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
        }

        // Tap the "Behavior" row inside the configuration list
        let behaviorCell = app.cells.staticTexts["Behavior"]
        if behaviorCell.waitForExistence(timeout: 5) {
            behaviorCell.tap()
        }
    }

    // MARK: - Visibility Tests

    @MainActor
    func testBehaviorSettingsScreenLoads() throws {
        navigateToBehaviorSettings()

        // The screen title or a section heading should be visible
        let receiverControlHeading = app.staticTexts["Receiver Control"]
        XCTAssertTrue(
            receiverControlHeading.waitForExistence(timeout: 5),
            "Receiver Control heading should be visible on the Behavior settings screen"
        )
    }

    @MainActor
    func testAutoRXAtStartToggleIsVisible() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Auto RX at start"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Auto RX at start toggle should be visible"
        )
    }

    @MainActor
    func testAutoCQReplyToggleIsVisible() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Reply to CQ received"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Reply to CQ received toggle should be visible"
        )
    }

    @MainActor
    func testAutoCQNewBandModeToggleIsVisible() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Only if new band/mode"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Only if new band/mode toggle should be visible"
        )
    }

    @MainActor
    func testShowTXMessagesToggleIsVisible() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Show TX messages in RX list"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Show TX messages in RX list toggle should be visible"
        )
    }

    @MainActor
    func testHoldTXFrequencyToggleIsVisible() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Hold TX frequency"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Hold TX frequency toggle should be visible"
        )
    }

    @MainActor
    func testAutoSequencingToggleIsVisible() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Auto-sequence"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Auto-sequence toggle should be visible"
        )
    }

    @MainActor
    func testAutoQSOLoggingToggleIsVisible() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Auto QSO logging"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Auto QSO logging toggle should be visible"
        )
    }

    // MARK: - Section Heading Tests

    @MainActor
    func testAutoCQReplySectionHeadingIsVisible() throws {
        navigateToBehaviorSettings()

        XCTAssertTrue(
            app.staticTexts["Auto CQ Reply"].waitForExistence(timeout: 5),
            "Auto CQ Reply section heading should be visible"
        )
    }

    @MainActor
    func testDisplayTransmissionSectionHeadingIsVisible() throws {
        navigateToBehaviorSettings()

        XCTAssertTrue(
            app.staticTexts["Display & Transmission"].waitForExistence(timeout: 5),
            "Display & Transmission section heading should be visible"
        )
    }

    @MainActor
    func testQSOAutomationSectionHeadingIsVisible() throws {
        navigateToBehaviorSettings()

        XCTAssertTrue(
            app.staticTexts["QSO Automation"].waitForExistence(timeout: 5),
            "QSO Automation section heading should be visible"
        )
    }

    // MARK: - Toggle Interaction Tests

    @MainActor
    func testAutoRXAtStartToggleCanBeEnabled() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Auto RX at start"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Auto RX at start toggle not found")
            return
        }

        scrollToVisible(toggle)

        // Ensure it starts off
        if toggle.value as? String == "1" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "0", "Toggle should be off before tapping")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "Auto RX at start toggle should be on after tapping")
    }

    @MainActor
    func testAutoCQReplyToggleCanBeEnabled() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Reply to CQ received"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Reply to CQ received toggle not found")
            return
        }

        scrollToVisible(toggle)

        if toggle.value as? String == "1" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "0")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "Reply to CQ received toggle should be on after tapping")
    }

    @MainActor
    func testShowTXMessagesToggleCanBeEnabled() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Show TX messages in RX list"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Show TX messages in RX list toggle not found")
            return
        }

        scrollToVisible(toggle)

        if toggle.value as? String == "1" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "0")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "Show TX messages toggle should be on after tapping")
    }

    @MainActor
    func testHoldTXFrequencyToggleCanBeEnabled() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["Hold TX frequency"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Hold TX frequency toggle not found")
            return
        }

        scrollToVisible(toggle)

        if toggle.value as? String == "1" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "0")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "Hold TX frequency toggle should be on after tapping")
    }

    @MainActor
    func testAutoQSOLoggingToggleCanBeDisabled() throws {
        navigateToBehaviorSettings()

        // autoQSOLogging defaults to true, so we verify it starts on and can be turned off
        let toggle = app.switches["Auto QSO logging"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Auto QSO logging toggle not found")
            return
        }

        scrollToVisible(toggle)

        if toggle.value as? String == "0" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "Auto QSO logging should default to on")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0", "Auto QSO logging toggle should be off after tapping")
    }

    @MainActor
    func testAutoSequencingToggleCanBeDisabled() throws {
        navigateToBehaviorSettings()

        // autoSequencingEnabled defaults to true
        let toggle = app.switches["Auto-sequence"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Auto-sequence toggle not found")
            return
        }

        scrollToVisible(toggle)

        if toggle.value as? String == "0" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "Auto-sequence should default to on")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0", "Auto-sequence toggle should be off after tapping")
    }

    // MARK: - Help Button Tests

    @MainActor
    func testHelpButtonsAreAccessible() throws {
        navigateToBehaviorSettings()

        // Verify at least one Help button exists on the screen
        let helpButtons = app.buttons["Help"]
        XCTAssertTrue(
            helpButtons.waitForExistence(timeout: 5),
            "At least one Help button should be present on the Behavior settings screen"
        )
    }
}
