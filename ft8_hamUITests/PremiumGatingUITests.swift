//
//  PremiumGatingUITests.swift
//  ft8_hamUITests
//
//  Created by Pablo Turrion on 05/04/26.
//

import XCTest

// MARK: - Premium Gating UI Tests

/// UI tests that verify premium features are correctly blocked for non-premium users
/// and that the paywall is presented when a locked feature is accessed.
///
/// These tests run with the app in its default state (no StoreKit purchase) which
/// means `isPremiumUnlocked` is `false`. In DEBUG builds the debug-premium override
/// is explicitly disabled via the `-debug_premium_enabled 0` launch argument so
/// the tests are deterministic even when a developer has the debug toggle on.
///
/// Requirements:
/// - The app must be linked against FTHamPremium (as it is in the standard dev build)
///   so that the `#if canImport(FTHamPremium)` gating blocks are compiled in and
///   `PremiumLockedRow` entries are rendered for locked features.
final class PremiumGatingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        // Explicitly disable the DEBUG premium override so tests always run in
        // non-premium mode regardless of the last developer toggle state.
        app.launchArguments += ["-debug_premium_enabled", "0"]
        // Force the new ConfigurationView so premiumLocked_* identifiers are available.
        app.launchArguments += ["-debug.newConfigViewOverride", "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Navigation Helpers

    /// Opens the Configuration tab (labelled "Configuration" in the tab bar).
    @MainActor
    private func openSettingsTab() {
        let settingsTab = app.tabBars.buttons["Configuration"]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
        }
    }

    /// Scrolls until `element` is hittable, or gives up after `maxSwipes` attempts.
    /// Waits for any in-flight navigation animation to settle before starting to swipe.
    @MainActor
    private func scrollToVisible(_ element: XCUIElement, maxSwipes: Int = 5) {
        guard !element.isHittable else { return }
        // Let the navigation slide-in animation finish before touching the scroll view.
        let hittablePredicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittablePredicate, object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 1.5) == .completed { return }
        // iOS 16+ SwiftUI List renders as UICollectionView, not UITableView.
        // Try UITableView first, then UICollectionView, then an explicit ScrollView.
        // If none exist, fall back to a whole-screen swipe so we never crash.
        let table = app.tables.firstMatch
        let collectionView = app.collectionViews.firstMatch
        let scrollView = app.scrollViews.firstMatch
        let container: XCUIElement? = {
            if table.exists { return table }
            if collectionView.exists { return collectionView }
            if scrollView.exists { return scrollView }
            return nil
        }()
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            if let container {
                container.swipeUp()
            } else {
                app.swipeUp()
            }
            attempts += 1
        }
    }

    /// Opens the paywall through the locked CAT Control row.
    @MainActor
    private func openPaywallFromLockedRow() {
        let lockedRow = app.buttons["premiumLocked_cat_control"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        lockedRow.tap()
    }

    /// Dismisses a presented sheet using the "Done" cancel button if present,
    /// otherwise falls back to a swipe-down gesture.
    @MainActor
    private func dismissSheet() {
        let closeButton = app.buttons["paywall_close"]
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
            return
        }
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        } else {
            app.swipeDown()
        }
    }

    // MARK: - ConfigurationView: Locked Rows Visible

    @MainActor
    func testCATControlIsLockedForNonPremiumUsers() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_cat_control"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        XCTAssertTrue(
            lockedRow.isHittable,
            "CAT Control should appear as a locked premium row for non-premium users"
        )
    }

    @MainActor
    func testQRZLogbookIsLockedForNonPremiumUsers() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_qrz_logbook_sync"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        XCTAssertTrue(
            lockedRow.isHittable,
            "QRZ Logbook should appear as a locked premium row for non-premium users"
        )
    }

    @MainActor
    func testLoTWSyncIsLockedForNonPremiumUsers() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_lotw_sync"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        XCTAssertTrue(
            lockedRow.isHittable,
            "LoTW Sync should appear as a locked premium row for non-premium users"
        )
    }

    @MainActor
    func testEQSLSyncIsLockedForNonPremiumUsers() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_eqsl_sync"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        XCTAssertTrue(
            lockedRow.isHittable,
            "eQSL Sync should appear as a locked premium row for non-premium users"
        )
    }

    // MARK: - ConfigurationView: Paywall Shown on Tap

    @MainActor
    func testTappingLockedCATControlShowsPaywall() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_cat_control"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        lockedRow.tap()

        let paywallTitle = app.staticTexts["Unlock Premium Features"]
        XCTAssertTrue(
            paywallTitle.waitForExistence(timeout: 5),
            "Tapping the locked CAT Control row should present the paywall"
        )
    }

    @MainActor
    func testTappingLockedQRZLogbookShowsPaywall() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_qrz_logbook_sync"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        lockedRow.tap()

        let paywallTitle = app.staticTexts["Unlock Premium Features"]
        XCTAssertTrue(
            paywallTitle.waitForExistence(timeout: 5),
            "Tapping the locked QRZ Logbook row should present the paywall"
        )
    }

    @MainActor
    func testTappingLockedLoTWSyncShowsPaywall() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_lotw_sync"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        lockedRow.tap()

        let paywallTitle = app.staticTexts["Unlock Premium Features"]
        XCTAssertTrue(
            paywallTitle.waitForExistence(timeout: 5),
            "Tapping the locked LoTW Sync row should present the paywall"
        )
    }

    @MainActor
    func testTappingLockedEQSLSyncShowsPaywall() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_eqsl_sync"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        lockedRow.tap()

        let paywallTitle = app.staticTexts["Unlock Premium Features"]
        XCTAssertTrue(
            paywallTitle.waitForExistence(timeout: 5),
            "Tapping the locked eQSL Sync row should present the paywall"
        )
    }

    // MARK: - ConfigurationView: Reporting Row Locked

    @MainActor
    func testReportingIsLockedForNonPremiumUsers() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_psk_reporter"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        XCTAssertTrue(
            lockedRow.isHittable,
            "Reporting should appear as a locked premium row for non-premium users"
        )
        XCTAssertFalse(
            app.switches["toggle_pskReporterEnabled"].exists,
            "The PSK Reporter toggle must not be reachable from the list for non-premium users"
        )
    }

    @MainActor
    func testTappingLockedReportingShowsPaywall() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_psk_reporter"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        lockedRow.tap()

        let paywallTitle = app.staticTexts["Unlock Premium Features"]
        XCTAssertTrue(
            paywallTitle.waitForExistence(timeout: 5),
            "Tapping the locked Reporting row should present the paywall"
        )
    }

    // MARK: - Paywall Content

    @MainActor
    func testPaywallShowsCorrectContent() throws {
        openSettingsTab()

        openPaywallFromLockedRow()

        XCTAssertTrue(
            app.staticTexts["Unlock Premium Features"].waitForExistence(timeout: 5),
            "Paywall should show 'Unlock Premium Features' heading"
        )
        XCTAssertTrue(
            app.staticTexts["One payment. Forever"].waitForExistence(timeout: 5),
            "Paywall should show the one-time payment description"
        )
        XCTAssertTrue(
            app.buttons["Restore Purchase"].waitForExistence(timeout: 5),
            "Paywall should offer a Restore Purchase button"
        )
    }

    @MainActor
    func testPaywallListsPSKReporterFeature() throws {
        openSettingsTab()

        openPaywallFromLockedRow()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "PSK Reporter"))
                .firstMatch.waitForExistence(timeout: 5),
            "Paywall should list PSK Reporter as a premium feature"
        )
    }

    @MainActor
    func testPaywallListsCATControlFeature() throws {
        openSettingsTab()

        openPaywallFromLockedRow()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "CAT Control"))
                .firstMatch.waitForExistence(timeout: 5),
            "Paywall should list CAT Control as a premium feature"
        )
    }

    // MARK: - Paywall Dismissal

    @MainActor
    func testPaywallCanBeDismissed() throws {
        openSettingsTab()

        openPaywallFromLockedRow()

        XCTAssertTrue(
            app.staticTexts["Unlock Premium Features"].waitForExistence(timeout: 5),
            "Paywall should appear"
        )

        dismissSheet()

        // After dismissal the paywall heading should disappear
        XCTAssertFalse(
            app.staticTexts["Unlock Premium Features"].waitForExistence(timeout: 3),
            "Paywall should be dismissed after tapping Done"
        )
    }

    @MainActor
    func testPaywallDismissedAfterLockedFeatureTap() throws {
        openSettingsTab()

        let lockedRow = app.buttons["premiumLocked_cat_control"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 5))
        scrollToVisible(lockedRow)
        lockedRow.tap()

        XCTAssertTrue(
            app.staticTexts["Unlock Premium Features"].waitForExistence(timeout: 5),
            "Paywall should appear when locked CAT Control is tapped"
        )

        dismissSheet()

        XCTAssertFalse(
            app.staticTexts["Unlock Premium Features"].waitForExistence(timeout: 3),
            "Paywall should be dismissed"
        )
        // The locked row should still be visible after dismissal (user remains non-premium)
        XCTAssertTrue(
            app.buttons["premiumLocked_cat_control"].waitForExistence(timeout: 5),
            "CAT Control should still be locked after dismissing the paywall without purchasing"
        )
    }

    // MARK: - Premium Section

    @MainActor
    func testPremiumButtonOpensPaywallWithRestoreOption() throws {
        openSettingsTab()

        let becomePremium = app.buttons["button_become_premium"]
        XCTAssertTrue(becomePremium.waitForExistence(timeout: 5), "Free users should see Become Premium")
        scrollToVisible(becomePremium, maxSwipes: 10)
        becomePremium.tap()

        let restore = app.buttons["paywall_restore"]
        XCTAssertTrue(
            restore.waitForExistence(timeout: 5),
            "The paywall opened from settings should offer Restore Purchase"
        )
    }

    @MainActor
    func testPaywallFromPremiumSectionHasSingleCloseButton() throws {
        openSettingsTab()

        let becomePremium = app.buttons["button_become_premium"]
        XCTAssertTrue(becomePremium.waitForExistence(timeout: 5))
        scrollToVisible(becomePremium, maxSwipes: 10)
        becomePremium.tap()

        XCTAssertTrue(
            app.staticTexts["Unlock Premium Features"].waitForExistence(timeout: 5),
            "Paywall should appear"
        )
        let closeButtons = app.navigationBars.buttons.matching(
            NSPredicate(format: "label IN %@", ["Close", "Done"])
        )
        XCTAssertEqual(
            closeButtons.count,
            1,
            "The paywall sheet should show exactly one close button"
        )
    }
}
