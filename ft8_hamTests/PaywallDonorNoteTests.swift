//
//  PaywallDonorNoteTests.swift
//  ft8_hamTests
//
//  Past donors whose Premium did not unlock on its own ask by email for an
//  offer code and redeem it from the paywall. New tips still unlock nothing.
//

import XCTest
@testable import ft8_ham

final class PaywallDonorNoteTests: XCTestCase {

    func testMailLinkOpensAMessageToSupport() {
        let url = PaywallDonorNote.mailURL
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:ftham@turrion.dev?subject="), url.absoluteString)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "subject" })?.value, PaywallDonorNote.subject)
    }

    private func localized(_ key: String, _ language: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
        return try XCTUnwrap(Bundle(path: path)).localizedString(forKey: key, value: nil, table: nil)
    }

    private static let stepKeys = [
        "Email ftham@turrion.dev with the order ID from your Apple receipt for the donation.",
        "We reply with a one-time code.",
        "Tap Redeem Code and enter it.",
    ]

    func testThreeStepsInOrder() {
        XCTAssertEqual(PaywallDonorNote.steps.count, 3)
        XCTAssertTrue(PaywallDonorNote.steps[0].contains(PaywallDonorNote.email))
    }

    /// The first step sends donors to the same address the Email Us button opens.
    func testFirstStepNamesTheSupportAddressInEveryLanguage() throws {
        for language in ["en", "de", "es", "fr", "it"] {
            let text = try localized(Self.stepKeys[0], language)
            XCTAssertTrue(text.contains(PaywallDonorNote.email), "\(language): \(text)")
        }
    }

    func testStepsAreTranslated() throws {
        for language in ["de", "es", "fr", "it"] {
            for key in Self.stepKeys {
                XCTAssertNotEqual(try localized(key, language), key, "\(language): \(key)")
            }
        }
    }

    /// The last step names the Redeem Code button as the button itself reads.
    func testLastStepNamesTheRedeemButtonInEveryLanguage() throws {
        for language in ["en", "de", "es", "fr", "it"] {
            let button = try localized("Redeem Code", language)
            let step = try localized(Self.stepKeys[2], language)
            XCTAssertTrue(step.contains(button), "\(language): \(step) / \(button)")
        }
    }

    func testRedeemErrorHasAMessage() {
        XCTAssertFalse((OfferCodeRedeemer.RedeemError.noActiveScene.errorDescription ?? "").isEmpty)
    }

    /// A tip is never a premium entitlement. Only tips from before 1.3.0 count,
    /// through `PremiumManager.isLegacyDonation`.
    @MainActor
    func testTipsStillDoNotUnlockPremium() {
        for tip in PremiumManager.donationProductIDs {
            XCTAssertFalse(PremiumManager.grantsPremium(productID: tip), tip)
        }
        XCTAssertTrue(PremiumManager.grantsPremium(productID: PremiumManager.premiumProductID))
    }
}

/// Feature names on the paywall follow the device language.
final class PremiumFeatureNameLocalizationTests: XCTestCase {

    func testFeatureNamesAreTranslated() throws {
        // Brand names that stay the same in every language.
        let brands: Set<PremiumFeature> = [.pskReporter, .lotwSync, .eqslSync]
        for language in ["de", "es", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for feature in PremiumFeature.allCases {
                let english = feature.displayName
                let translated = bundle.localizedString(forKey: english, value: nil, table: nil)
                XCTAssertFalse(translated.isEmpty, "\(language): \(feature)")
                if !brands.contains(feature) && !(language == "es" && feature == .qrzLogbook) {
                    XCTAssertNotEqual(translated, english, "\(language): \(feature)")
                }
            }
        }
    }

    func testSpanishNamesMatchTheSettingsRows() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "es", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(bundle.localizedString(forKey: PremiumFeature.statistics.displayName, value: nil, table: nil), "Estadísticas")
        XCTAssertEqual(bundle.localizedString(forKey: PremiumFeature.catControl.displayName, value: nil, table: nil), "Control CAT")
        XCTAssertEqual(bundle.localizedString(forKey: PremiumFeature.bandHopping.displayName, value: nil, table: nil), "Salto de bandas")
    }
}
