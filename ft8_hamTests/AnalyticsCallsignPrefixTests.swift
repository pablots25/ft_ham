//
//  AnalyticsCallsignPrefixTests.swift
//  ft8_hamTests
//
//  The country_not_found event must carry only a callsign prefix, never the
//  full callsign, so analytics stay free of personal identifiers.
//

import XCTest
@testable import ft8_ham

final class AnalyticsCallsignPrefixTests: XCTestCase {

    func test_standardCallsigns_returnLettersAndDigit() {
        XCTAssertEqual(AnalyticsManager.callsignPrefix("EA4IQL"), "EA4")
        XCTAssertEqual(AnalyticsManager.callsignPrefix("K1ABC"), "K1")
        XCTAssertEqual(AnalyticsManager.callsignPrefix("VP2EAB"), "VP2")
        XCTAssertEqual(AnalyticsManager.callsignPrefix("JA1XYZ"), "JA1")
    }

    func test_digitLedPrefix_keepsLeadingDigit() {
        XCTAssertEqual(AnalyticsManager.callsignPrefix("3DA0XYZ"), "3DA0")
        XCTAssertEqual(AnalyticsManager.callsignPrefix("9A1AA"), "9A1")
    }

    func test_lowercaseInput_isUppercased() {
        XCTAssertEqual(AnalyticsManager.callsignPrefix("k1abc"), "K1")
    }

    func test_noPrefixShape_fallsBackToTwoCharacters() {
        XCTAssertEqual(AnalyticsManager.callsignPrefix("<garbage>"), "<G")
        XCTAssertEqual(AnalyticsManager.callsignPrefix("ABC"), "AB")
        XCTAssertEqual(AnalyticsManager.callsignPrefix(""), "")
    }

    func test_neverReturnsTheFullCallsign() {
        for call in ["EA4IQL", "K1ABC", "VP2EAB", "3DA0XYZ", "W1AW", "G4ABC"] {
            XCTAssertNotEqual(AnalyticsManager.callsignPrefix(call), call, "Full callsign leaked for \(call)")
        }
    }
}
