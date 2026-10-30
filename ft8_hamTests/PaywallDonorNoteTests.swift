//
//  PaywallDonorNoteTests.swift
//  ft8_hamTests
//
//  Past donors get Premium through an offer code they ask for by email.
//  Tips themselves still unlock nothing.
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

    /// The note sends donors to the same address it shows.
    func testNoteNamesTheSameAddressInEveryLanguage() throws {
        let key = "If you donated in an earlier version, write to ftham@turrion.dev and we will send you a code for free Premium."
        for language in ["en", "de", "es", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let text = try XCTUnwrap(Bundle(path: path)).localizedString(forKey: key, value: nil, table: nil)
            XCTAssertTrue(text.contains(PaywallDonorNote.email), "\(language): \(text)")
            if language != "en" { XCTAssertNotEqual(text, key, language) }
        }
    }

    /// Donors are handled with offer codes, not by unlocking premium for tips.
    @MainActor
    func testTipsStillDoNotUnlockPremium() {
        for tip in PremiumManager.donationProductIDs {
            XCTAssertFalse(PremiumManager.grantsPremium(productID: tip), tip)
        }
        XCTAssertTrue(PremiumManager.grantsPremium(productID: PremiumManager.premiumProductID))
    }
}
