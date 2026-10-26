//
//  ControlButtonsLocalizationTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 26/10/26.
//

import XCTest
@testable import ft8_ham

/// The TX/RX control buttons and the Behavior settings row must be
/// translated with one consistent verb per language.
final class ControlButtonsLocalizationTests: XCTestCase {

    private func localized(_ key: String, _ language: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle(for: FT8ViewModel.self).path(forResource: language, ofType: "lproj"),
            "missing \(language).lproj"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func test_spanishControlButtons_useDetenerAndIniciar() throws {
        XCTAssertEqual(try localized("Stop TX", "es"), "Detener TX")
        XCTAssertEqual(try localized("Stop RX", "es"), "Detener RX")
        XCTAssertEqual(try localized("Start RX", "es"), "Iniciar RX")
        XCTAssertEqual(try localized("Stop all", "es"), "Detener todo")
    }

    func test_controlButtons_areTranslatedInEveryLanguage() throws {
        for language in ["es", "de", "fr", "it"] {
            for key in ["Stop TX", "Stop RX", "Start RX"] {
                XCTAssertNotEqual(try localized(key, language), key, "\(key) untranslated in \(language)")
            }
        }
    }

    func test_behaviorRow_isTranslated() throws {
        XCTAssertEqual(try localized("Behavior", "es"), "Comportamiento")
        XCTAssertEqual(try localized("Behavior", "de"), "Verhalten")
        XCTAssertEqual(try localized("Behavior", "fr"), "Comportement")
        XCTAssertEqual(try localized("Behavior", "it"), "Comportamento")
    }
}
