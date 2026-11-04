// ValidatorsTests.swift
// ft8_hamTests
//
// Unit tests for the pure parsing functions in Validators.swift:
//   isValidCallsign(_:), isValidLocator(_:), isSignalReport(_:)
//
// These are zero-dependency, value-type functions — no @MainActor needed.

import XCTest
@testable import ft8_ham

/// Extended tests for the global validator functions defined in `Validators.swift`.
final class ValidatorsExtendedTests: XCTestCase {

    // MARK: - isValidCallsign

    // MARK: Happy paths

    /// Standard ITU callsign: 2-char prefix, digit, 3-char suffix.
    func test_isValidCallsign_standardFormat_returnsTrue() {
        XCTAssertTrue(isValidCallsign("EA4IQL"))
    }

    /// 1-character national prefix (e.g. K, W, G, F, I, R).
    func test_isValidCallsign_singleCharPrefix_returnsTrue() {
        XCTAssertTrue(isValidCallsign("K1ABC"))
        XCTAssertTrue(isValidCallsign("W9XYZ"))
        XCTAssertTrue(isValidCallsign("G4ABC"))
    }

    /// 3-character prefix with 1-character suffix.
    func test_isValidCallsign_threePrefixOneLetterSuffix_returnsTrue() {
        XCTAssertTrue(isValidCallsign("VE3A"))
        XCTAssertTrue(isValidCallsign("VK2Z"))
    }

    /// Portable suffix /P is valid.
    func test_isValidCallsign_portableSuffix_returnsTrue() {
        XCTAssertTrue(isValidCallsign("EA4IQL/P"))
    }

    /// Maritime mobile suffix /MM is valid.
    func test_isValidCallsign_maritimeMobileSuffix_returnsTrue() {
        XCTAssertTrue(isValidCallsign("G3ABC/MM"))
    }

    /// QRP suffix is valid.
    func test_isValidCallsign_qrpSuffix_returnsTrue() {
        XCTAssertTrue(isValidCallsign("W1AW/QRP"))
    }

    /// Numeric suffix is valid (e.g. guest operating from another district).
    func test_isValidCallsign_numericSuffix_returnsTrue() {
        XCTAssertTrue(isValidCallsign("K1ABC/1"))
    }

    /// Alphabetic suffix of up to 3 chars is valid.
    func test_isValidCallsign_alphaThreeCharSuffix_returnsTrue() {
        XCTAssertTrue(isValidCallsign("VE3ABC/VE3"))
    }

    /// Lowercase input must be normalised internally.
    func test_isValidCallsign_lowercase_returnsTrue() {
        XCTAssertTrue(isValidCallsign("ea4iql"))
    }

    // MARK: Forbidden protocol tokens

    func test_isValidCallsign_cqToken_returnsFalse() {
        XCTAssertFalse(isValidCallsign("CQ"))
    }

    func test_isValidCallsign_qrzToken_returnsFalse() {
        XCTAssertFalse(isValidCallsign("QRZ"))
    }

    func test_isValidCallsign_deToken_returnsFalse() {
        XCTAssertFalse(isValidCallsign("DE"))
    }

    func test_isValidCallsign_rr73Token_returnsFalse() {
        XCTAssertFalse(isValidCallsign("RR73"))
    }

    func test_isValidCallsign_73Token_returnsFalse() {
        XCTAssertFalse(isValidCallsign("73"))
    }

    // MARK: Locator / SNR rejection

    /// "IN76" looks like a locator — must be rejected as a callsign.
    func test_isValidCallsign_maidenheadLocator_returnsFalse() {
        XCTAssertFalse(isValidCallsign("IN76"))
        XCTAssertFalse(isValidCallsign("FN20"))
        XCTAssertFalse(isValidCallsign("JO01"))
    }

    /// Signal report tokens must not be accepted as callsigns.
    func test_isValidCallsign_signalReport_returnsFalse() {
        XCTAssertFalse(isValidCallsign("+05"))
        XCTAssertFalse(isValidCallsign("-10"))
        XCTAssertFalse(isValidCallsign("R-08"))
    }

    // MARK: Edge / invalid format

    func test_isValidCallsign_emptyString_returnsFalse() {
        XCTAssertFalse(isValidCallsign(""))
    }

    /// All letters with no digit are not valid ITU callsigns.
    func test_isValidCallsign_noDigit_returnsFalse() {
        XCTAssertFalse(isValidCallsign("ABCDEF"))
    }

    /// Suffix with two slashes is not valid.
    func test_isValidCallsign_doubleSlashSuffix_returnsFalse() {
        XCTAssertFalse(isValidCallsign("EA4IQL/P/MM"))
    }

    // MARK: - isValidLocator

    // MARK: Happy paths

    /// Standard 4-character Maidenhead squares A–R + digit × 2.
    func test_isValidLocator_standard4Char_returnsTrue() {
        XCTAssertTrue(isValidLocator("IN76"))
        XCTAssertTrue(isValidLocator("FN20"))
        XCTAssertTrue(isValidLocator("JO01"))
        XCTAssertTrue(isValidLocator("AR00"))
        XCTAssertTrue(isValidLocator("RR99"))
    }

    /// Lowercase must normalise correctly.
    func test_isValidLocator_lowercase_returnsTrue() {
        XCTAssertTrue(isValidLocator("in76"))
        XCTAssertTrue(isValidLocator("fn20"))
    }

    // MARK: Edge / invalid

    /// "RR73" starts with two letters and two digits but must be explicitly excluded.
    func test_isValidLocator_rr73_returnsFalse() {
        XCTAssertFalse(isValidLocator("RR73"))
    }

    func test_isValidLocator_emptyString_returnsFalse() {
        XCTAssertFalse(isValidLocator(""))
    }

    /// 6-character extended Maidenhead locators are not accepted by this function.
    func test_isValidLocator_sixCharExtended_returnsFalse() {
        XCTAssertFalse(isValidLocator("IN76AB"))
    }

    /// 2-character field locator is insufficient.
    func test_isValidLocator_twoChar_returnsFalse() {
        XCTAssertFalse(isValidLocator("IN"))
    }

    /// Out-of-range first character (S–Z in field row).
    func test_isValidLocator_invalidFieldRow_returnsFalse() {
        XCTAssertFalse(isValidLocator("SA00"))
        XCTAssertFalse(isValidLocator("ZZ99"))
    }

    /// Digit where a letter is expected.
    func test_isValidLocator_digitInLetterPosition_returnsFalse() {
        XCTAssertFalse(isValidLocator("1A23"))
    }

    // MARK: - isSignalReport

    // MARK: Happy paths

    /// Single "0" is a special-case valid report.
    func test_isSignalReport_zero_returnsTrue() {
        XCTAssertTrue(isSignalReport(Substring("0")))
    }

    /// Positive report with explicit sign.
    func test_isSignalReport_positiveSigned_returnsTrue() {
        XCTAssertTrue(isSignalReport(Substring("+05")))
        XCTAssertTrue(isSignalReport(Substring("+30")))
        XCTAssertTrue(isSignalReport(Substring("+1")))
    }

    /// Negative report with explicit sign.
    func test_isSignalReport_negativeSigned_returnsTrue() {
        XCTAssertTrue(isSignalReport(Substring("-10")))
        XCTAssertTrue(isSignalReport(Substring("-30")))
        XCTAssertTrue(isSignalReport(Substring("-5")))
    }

    /// Positive report with R-prefix acknowledgement.
    func test_isSignalReport_rPlusPrefix_returnsTrue() {
        XCTAssertTrue(isSignalReport(Substring("R+12")))
        XCTAssertTrue(isSignalReport(Substring("R+05")))
    }

    /// Negative report with R-prefix acknowledgement.
    func test_isSignalReport_rMinusPrefix_returnsTrue() {
        XCTAssertTrue(isSignalReport(Substring("R-08")))
        XCTAssertTrue(isSignalReport(Substring("R-30")))
    }

    /// R-prefix followed by single digit.
    func test_isSignalReport_rPrefixSingleDigit_returnsTrue() {
        XCTAssertTrue(isSignalReport(Substring("R+5")))
        XCTAssertTrue(isSignalReport(Substring("R-5")))
    }

    /// Plain unsigned number (e.g. "12").
    func test_isSignalReport_plainUnsigned_returnsTrue() {
        XCTAssertTrue(isSignalReport(Substring("12")))
        XCTAssertTrue(isSignalReport(Substring("5")))
    }

    // MARK: Out-of-range / invalid

    func test_isSignalReport_emptyString_returnsFalse() {
        XCTAssertFalse(isSignalReport(Substring("")))
    }

    /// Three-digit values cannot appear in the 1–2 digit range.
    func test_isSignalReport_threeDigitValue_returnsFalse() {
        XCTAssertFalse(isSignalReport(Substring("+100")))
        XCTAssertFalse(isSignalReport(Substring("-100")))
    }

    /// Locator tokens must not be treated as signal reports.
    func test_isSignalReport_locatorToken_returnsFalse() {
        XCTAssertFalse(isSignalReport(Substring("IN76")))
        XCTAssertFalse(isSignalReport(Substring("FN20")))
    }

    /// Protocol words are not reports.
    func test_isSignalReport_rr73Token_returnsFalse() {
        XCTAssertFalse(isSignalReport(Substring("RR73")))
    }

    func test_isSignalReport_73Token_returnsFalse() {
        XCTAssertFalse(isSignalReport(Substring("73")))
    }

    /// Pure letter strings are not reports.
    func test_isSignalReport_allLetters_returnsFalse() {
        XCTAssertFalse(isSignalReport(Substring("ABC")))
    }
}
