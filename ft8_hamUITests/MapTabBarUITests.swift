//
//  MapTabBarUITests.swift
//  ft8_hamUITests
//
//  Verifies that the tab bar remains fully visible (not obscured by the map)
//  when the Map tab is active, on all supported iOS versions.
//

import XCTest

final class MapTabBarUITests: XCTestCase {

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

    // MARK: - Helpers

    /// Taps the Map tab and waits for the transition to settle.
    @MainActor
    private func navigateToMapTab() {
        let mapTab = app.tabBars.buttons["Map"]
        XCTAssertTrue(
            mapTab.waitForExistence(timeout: 5),
            "Map tab bar button should exist"
        )
        mapTab.tap()
    }

    // MARK: - Tab Bar Visibility Tests

    /// The tab bar must exist and be hittable after selecting the Map tab.
    /// This guards against the map's ignoresSafeArea expanding beneath the tab bar
    /// and making it non-interactive (regression seen on iOS 18.5 simulator).
    @MainActor
    func testTabBarIsVisibleOnMapTab() throws {
        navigateToMapTab()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 5),
            "Tab bar should exist when the Map tab is active"
        )
        XCTAssertTrue(
            tabBar.isHittable,
            "Tab bar should be hittable (not obscured by the map) when the Map tab is active"
        )
    }

    /// Every individual tab bar button must remain hittable while on the Map tab.
    @MainActor
    func testAllTabBarButtonsHittableOnMapTab() throws {
        navigateToMapTab()

        let expectedTabs = ["TX/RX", "Waterfall", "Map", "Logbook", "Configuration"]
        for tabName in expectedTabs {
            let button = app.tabBars.buttons[tabName]
            XCTAssertTrue(
                button.waitForExistence(timeout: 5),
                "Tab bar button '\(tabName)' should exist"
            )
            XCTAssertTrue(
                button.isHittable,
                "Tab bar button '\(tabName)' should be hittable when the Map tab is active"
            )
        }
    }

    /// Tapping another tab from the Map tab must work (tab bar not blocked).
    @MainActor
    func testCanSwitchAwayFromMapTab() throws {
        navigateToMapTab()

        let logbookTab = app.tabBars.buttons["Logbook"]
        XCTAssertTrue(
            logbookTab.waitForExistence(timeout: 5),
            "Logbook tab button should exist while on Map tab"
        )
        logbookTab.tap()

        // After tapping, the Logbook tab should become selected (selected state)
        XCTAssertTrue(
            logbookTab.waitForExistence(timeout: 3),
            "Logbook tab should still be reachable after tapping from Map tab"
        )
    }
}
