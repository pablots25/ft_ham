//
//  LogSyncLocalizationTests.swift
//  ft8_hamTests
//
//  The QRZ, LoTW and eQSL settings live in the premium package. Their
//  strings must come from the package's own catalog, or they show in
//  English whatever the device language is.
//

import XCTest
@testable import ft8_ham
#if canImport(FTHamPremium)
import FTHamPremium
#endif

final class LogSyncLocalizationTests: XCTestCase {

    #if canImport(FTHamPremium)

    private static let languages = ["de", "es", "fr", "it"]

    /// One string from each settings screen and from the service errors.
    private static let sampleKeys = [
        "API key stored in Keychain",
        "Certificate stored in Keychain",
        "Credentials stored in Keychain",
        "Auto-upload on QSO log",
        "Confirmation check interval",
        "Remove LoTW Certificate?",
        "No QRZ API key configured",
        "LoTW upload failed (HTTP %@)",
        "Invalid .p12 certificate (OSStatus %@). Check the password.",
        "Item not found in Keychain",
    ]

    private func premiumBundle(file: StaticString = #filePath, line: UInt = #line) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "FTHamPremium_FTHamPremium", withExtension: "bundle"),
            "Premium resource bundle missing from the app",
            file: file, line: line
        )
        return try XCTUnwrap(Bundle(url: url), file: file, line: line)
    }

    private func localized(_ key: String, language: String, in bundle: Bundle) throws -> String {
        let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"), "\(language).lproj missing")
        let lproj = try XCTUnwrap(Bundle(path: path))
        return lproj.localizedString(forKey: key, value: nil, table: nil)
    }

    func testSettingsAndErrorsAreTranslated() throws {
        let bundle = try premiumBundle()
        for language in Self.languages {
            for key in Self.sampleKeys {
                let value = try localized(key, language: language, in: bundle)
                XCTAssertNotEqual(value, key, "\(language): \(key)")
                XCTAssertFalse(value.isEmpty, "\(language): \(key)")
            }
        }
    }

    /// Translations keep the placeholder, or the code is dropped from the message.
    func testFormatPlaceholdersSurviveTranslation() throws {
        let bundle = try premiumBundle()
        let keys = [
            "LoTW upload failed (HTTP %@)",
            "QRZ upload failed (HTTP %@)",
            "eQSL HTTP error %@",
            "Key signing failed (OSStatus %@)",
            "Keychain store failed (OSStatus %@)",
        ]
        for language in Self.languages {
            for key in keys {
                let value = try localized(key, language: language, in: bundle)
                XCTAssertTrue(value.contains("%@"), "\(language): \(value)")
            }
        }
    }

    /// Status and HTTP codes are passed as text, so no locale adds a
    /// thousands separator (regression: "OSStatus -25.293" in Spanish).
    func testErrorCodesAreNotGroupedInTranslations() throws {
        let bundle = try premiumBundle()
        let format = try localized("Invalid .p12 certificate (OSStatus %@). Check the password.", language: "es", in: bundle)
        let message = String(format: format, locale: Locale(identifier: "es_ES"), String(-25293))
        XCTAssertTrue(message.contains("-25293"), message)
    }

    func testPendingUploadsArePlural() throws {
        let bundle = try premiumBundle()
        let english = try localized("%lld QSO(s) pending upload", language: "en", in: bundle)
        XCTAssertEqual(String.localizedStringWithFormat(english, 1), "1 QSO pending upload")
        XCTAssertEqual(String.localizedStringWithFormat(english, 3), "3 QSOs pending upload")
    }

    func testErrorDescriptionsAreDistinctAndFollowCopyStyle() {
        let errors: [LocalizedError] = [
            LoTWError.invalidCertificate(-25293),
            LoTWError.identityExtractionFailed,
            LoTWError.signingFailed(-1),
            LoTWError.encodingFailed,
            KeychainHelper.KeychainError.encodingFailed,
            KeychainHelper.KeychainError.decodingFailed,
            KeychainHelper.KeychainError.storeFailed(-1),
            KeychainHelper.KeychainError.fetchFailed(-1),
            KeychainHelper.KeychainError.notFound,
        ]
        let descriptions = errors.compactMap(\.errorDescription)
        XCTAssertEqual(descriptions.count, errors.count)
        XCTAssertEqual(Set(descriptions).count, descriptions.count)
        for description in descriptions {
            XCTAssertFalse(description.contains("—"), description)
        }
        XCTAssertTrue(descriptions[0].contains("-25293"), descriptions[0])
    }

    #endif
}

/// App strings found untranslated or out of date while checking the
/// log sync screens in Spanish.
final class WaterfallAndLogSyncCopyTests: XCTestCase {

    private func spanish(_ key: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "es", ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path)).localizedString(forKey: key, value: nil, table: nil)
    }

    func testLogSyncingHeaderHasAccent() throws {
        XCTAssertEqual(try spanish("Log Syncing"), "Sincronización de logs")
    }

    func testWaterfallSliderValuesAreTranslated() throws {
        XCTAssertEqual(try spanish("%@ dB below noise"), "%@ dB bajo el ruido")
        XCTAssertEqual(try spanish("%@ dB range"), "%@ dB de rango")
    }

    /// A plain tap no longer moves the TX frequency, so the footnote must
    /// not say it does.
    func testTapFootnoteMatchesTapRules() throws {
        let key = "With this off, a tap does nothing. Holding a signal still replies. To move the transmit frequency, turn on the frequency button first."
        XCTAssertNotEqual(try spanish(key), key)
        XCTAssertEqual(
            WaterfallTapRouter.outcome(tapToReply: false, gesture: .single, isSecondTap: false, hasReplyableLabel: true),
            .ignore
        )
    }
}
