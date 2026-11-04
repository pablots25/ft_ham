//
//  ICloudSyncUITests.swift
//  ft8_hamUITests
//
//  Created by Pablo Turrion on 14/09/26.
//

import XCTest

/// Opens the iCloud Sync screen as a premium user. `CKContainer(identifier:)`
/// traps when the binary lacks the iCloud entitlement, so this guards the
/// project wiring as much as the view.
final class ICloudSyncUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchArguments += ["-debug_premium_enabled", "1"]
        app.launchArguments += ["-debug.newConfigViewOverride", "1"]
        app.launchArguments += ["-debug.enableICloudSyncOverride", "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testICloudSyncScreenOpensWithoutCrashing() throws {
        let settingsTab = app.tabBars.buttons["Configuration"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        // The Logbook section sits below the fold, so its rows only exist
        // once the list is scrolled to them.
        let row = app.cells.staticTexts["iCloud Sync"]
        XCTAssertTrue(app.scrollToElement(row), "iCloud Sync row should be listed under Logbook")
        row.tap()

        let toggle = app.switches["toggle_iCloudLogbookSync"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "The iCloud Sync screen should show its toggle"
        )
        // The account-status task has had time to touch CloudKit by now; the
        // app must still be running.
        XCTAssertEqual(app.state, .runningForeground)
    }
}
