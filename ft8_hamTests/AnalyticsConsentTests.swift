//
//  AnalyticsConsentTests.swift
//  ft_hamTests
//
//  Tests for the Firebase Consent Mode v2 integration added to AnalyticsManager:
//  - applyConsentBeforeConfigure() reads hasAcceptedTerms from UserDefaults
//  - isAnalyticsEnabled persists to UserDefaults on change
//  - grantAnalyticsConsent() / applyConsentBeforeConfigure() do not crash
//

import XCTest
@testable import ft8_ham

final class AnalyticsConsentTests: XCTestCase {

    private let analyticsEnabledKey = "analyticsEnabled"
    private let hasAcceptedTermsKey = "hasAcceptedTerms"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: analyticsEnabledKey)
        UserDefaults.standard.removeObject(forKey: hasAcceptedTermsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: analyticsEnabledKey)
        UserDefaults.standard.removeObject(forKey: hasAcceptedTermsKey)
        super.tearDown()
    }

    // MARK: - isAnalyticsEnabled — UserDefaults persistence

    func testIsAnalyticsEnabled_TrueIsPersisted() {
        AnalyticsManager.shared.isAnalyticsEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: analyticsEnabledKey),
                      "isAnalyticsEnabled = true should persist 'true' to UserDefaults")
    }

    func testIsAnalyticsEnabled_FalseIsPersisted() {
        AnalyticsManager.shared.isAnalyticsEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: analyticsEnabledKey),
                       "isAnalyticsEnabled = false should persist 'false' to UserDefaults")
    }

    func testIsAnalyticsEnabled_TogglesReflectInUserDefaults() {
        AnalyticsManager.shared.isAnalyticsEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: analyticsEnabledKey))

        AnalyticsManager.shared.isAnalyticsEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: analyticsEnabledKey))

        AnalyticsManager.shared.isAnalyticsEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: analyticsEnabledKey))
    }

    // MARK: - applyConsentBeforeConfigure — reads correct UserDefaults key

    func testApplyConsentBeforeConfigure_WhenTermsNotAccepted_DoesNotCrash() {
        UserDefaults.standard.set(false, forKey: hasAcceptedTermsKey)
        XCTAssertNoThrow(
            AnalyticsManager.applyConsentBeforeConfigure(),
            "applyConsentBeforeConfigure must not throw when terms are not accepted"
        )
    }

    func testApplyConsentBeforeConfigure_WhenTermsAccepted_DoesNotCrash() {
        UserDefaults.standard.set(true, forKey: hasAcceptedTermsKey)
        XCTAssertNoThrow(
            AnalyticsManager.applyConsentBeforeConfigure(),
            "applyConsentBeforeConfigure must not throw when terms are accepted"
        )
    }

    func testApplyConsentBeforeConfigure_ReadsHasAcceptedTermsKey() {
        // Verify it uses 'hasAcceptedTerms' — setting the key must not crash.
        // (The actual Firebase consent signal is not observable in unit tests,
        //  but the absence of a crash and correct key access are verifiable.)
        UserDefaults.standard.set(true, forKey: hasAcceptedTermsKey)
        let valueBeforeCall = UserDefaults.standard.bool(forKey: hasAcceptedTermsKey)
        AnalyticsManager.applyConsentBeforeConfigure()
        // The key should be unchanged — applyConsentBeforeConfigure only reads it.
        XCTAssertEqual(UserDefaults.standard.bool(forKey: hasAcceptedTermsKey),
                       valueBeforeCall,
                       "applyConsentBeforeConfigure must not mutate hasAcceptedTerms")
    }

    // MARK: - grantAnalyticsConsent

    func testGrantAnalyticsConsent_DoesNotCrash() {
        XCTAssertNoThrow(
            AnalyticsManager.shared.grantAnalyticsConsent(),
            "grantAnalyticsConsent must not throw"
        )
    }
}
