//
//  CatalogCompletenessTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 12/11/26.
//

import XCTest
@testable import ft8_ham

/// Strings that had no German, French or Italian entry, which the release
/// check (scripts/check_strings.py --strict) reports and blocks a tag on.
final class CatalogCompletenessTests: XCTestCase {

    private let languages = ["de", "fr", "it"]

    private func localized(_ key: String, _ language: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle(for: FT8ViewModel.self).path(forResource: language, ofType: "lproj"),
            "missing \(language).lproj"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        // A sentinel default tells a missing entry apart from one equal to its key.
        return bundle.localizedString(forKey: key, value: "<missing>", table: nil)
    }

    func test_noButton_isTranslated() throws {
        XCTAssertEqual(try localized("No", "de"), "Nein")
        XCTAssertEqual(try localized("No", "fr"), "Non")
        XCTAssertEqual(try localized("No", "it"), "No")
    }

    func test_technicalLabels_haveAnEntryInEveryLanguage() throws {
        for language in languages {
            for key in ["OK", "TX", "(TX)", "(RX)", "FT4", "FT8", "dB", "Δt"] {
                XCTAssertEqual(try localized(key, language), key, "\(key) has no \(language) entry")
            }
        }
    }

    func test_waterfallHelp_isTranslatedInEveryLanguage() throws {
        for language in languages {
            for key in ["Waterfall flatten help", "Waterfall level help", "Waterfall palette help"] {
                let value = try localized(key, language)
                XCTAssertNotEqual(value, "<missing>", "\(key) has no \(language) entry")
                XCTAssertNotEqual(value, key, "\(key) shows its key in \(language)")
            }
        }
    }

    func test_waterfallHelp_hasEnglishText() throws {
        let value = try localized("Waterfall palette help", "en")
        XCTAssertTrue(value.hasPrefix("Color scale of the waterfall"), value)
    }
}
