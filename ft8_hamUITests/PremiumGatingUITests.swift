//
//  PremiumGatingUITests.swift
//  ft8_hamUITests
//
//  Created by GitHub Copilot on 05/04/26.
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

    /// Navigates to the Behavior settings screen.
    @MainActor
    private func navigateToBehaviorSettings() {
        openSettingsTab()
        let cell = app.cells.staticTexts["Behavior"]
        if cell.waitForExistence(timeout: 5) {
            cell.tap()
        }
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

    // MARK: - BehaviorSettingsView: PSK Reporter Section Blocked

    @MainActor
    func testPSKReporterToggleIsDisabledForNonPremiumUsers() throws {
        navigateToBehaviorSettings()

        let toggle = app.switches["toggle_pskReporterEnabled"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "PSK Reporter toggle should exist in Behavior settings"
        )
        XCTAssertFalse(
            toggle.isEnabled,
            "PSK Reporter toggle should be disabled for non-premium users"
        )
    }

    @MainActor
    func testPSKReporterSectionShowsPaywallWhenTapped() throws {
        navigateToBehaviorSettings()

        // The PSK Reporter section has a transparent overlay button that triggers
        // the paywall when tapped
        let lockOverlay = app.buttons["button_pskReporterLock"]
        XCTAssertTrue(
            lockOverlay.waitForExistence(timeout: 5),
            "The PSK Reporter premium lock overlay should be present for non-premium users"
        )
        scrollToVisible(lockOverlay)
        lockOverlay.tap()

        let paywallTitle = app.staticTexts["Unlock Premium Features"]
        XCTAssertTrue(
            paywallTitle.waitForExistence(timeout: 5),
            "Tapping the PSK Reporter lock overlay should present the paywall"
        )
    }

    // MARK: - Paywall Content

    @MainActor
    func testPaywallShowsCorrectContent() throws {
        openSettingsTab()

        // Open paywall via the "Become Premium" row in the Support section
        let becomePremiumButton = app.buttons["Become Premium"]
        scrollToVisible(becomePremiumButton, maxSwipes: 10)
        XCTAssertTrue(becomePremiumButton.waitForExistence(timeout: 5))
        becomePremiumButton.tap()

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

        let becomePremiumButton = app.buttons["Become Premium"]
        scrollToVisible(becomePremiumButton, maxSwipes: 10)
        XCTAssertTrue(becomePremiumButton.waitForExistence(timeout: 5))
        becomePremiumButton.tap()

        XCTAssertTrue(
            app.staticTexts["PSK Reporter integration"].waitForExistence(timeout: 5),
            "Paywall should list PSK Reporter integration as a premium feature"
        )
    }

    @MainActor
    func testPaywallListsCATControlFeature() throws {
        openSettingsTab()

        let becomePremiumButton = app.buttons["Become Premium"]
        scrollToVisible(becomePremiumButton, maxSwipes: 10)
        XCTAssertTrue(becomePremiumButton.waitForExistence(timeout: 5))
        becomePremiumButton.tap()

        XCTAssertTrue(
            app.staticTexts["CAT Control"].waitForExistence(timeout: 5),
            "Paywall should list CAT Control as a premium feature"
        )
    }

    // MARK: - Paywall Dismissal

    @MainActor
    func testPaywallCanBeDismissed() throws {
        openSettingsTab()

        let becomePremiumButton = app.buttons["Become Premium"]
        scrollToVisible(becomePremiumButton, maxSwipes: 10)
        XCTAssertTrue(becomePremiumButton.waitForExistence(timeout: 5))
        becomePremiumButton.tap()

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
}
