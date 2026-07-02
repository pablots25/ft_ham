// FT8MessageComposerTests.swift
// ft8_hamTests
//
// Tests for FT8MessageComposer.generateMessages(callsign:locator:dxCallsign:dxLocator:snrToSend:includeGrid:)
// covering: message count, content at each index, SNR clamping, CQ modifiers,
// grid-suppression flag, and empty-DX fallback.

import XCTest
@testable import ft8_ham

/// Additional unit tests for `FT8MessageComposer.generateMessages(...)`.
final class FT8MessageComposerAdditionalTests: XCTestCase {

    // MARK: - Test fixtures

    private let callsign  = "EA4IQL"
    private let locator   = "IN76"
    private let dxCall    = "K1ABC"
    private let dxLocator = "FN20"
    private let snr       = 5.0     // clean +05

    private var sut: FT8MessageComposer!

    override func setUp() {
        super.setUp()
        sut = FT8MessageComposer()
        // Clean up every UserDefaults key touched by the composer
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
        UserDefaults.standard.removeObject(forKey: "cqIncludeGrid")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
        UserDefaults.standard.removeObject(forKey: "cqIncludeGrid")
        sut = nil
        super.tearDown()
    }

    // MARK: - Count & length contract

    /// The composer must always return exactly 7 messages.
    func test_generateMessages_alwaysReturnsSevenElements() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertEqual(messages.count, 7)
    }

    /// Every element must fit within the ft8_lib's FTX_MAX_MESSAGE_LENGTH (35, including null terminator).
    func test_generateMessages_allMessagesWithinProtocolLimit() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        for (index, msg) in messages.enumerated() {
            XCTAssertLessThanOrEqual(msg.count, 34,
                "Message at index \(index) exceeds protocol limit: '\(msg)'")
        }
    }

    // MARK: - Index-0: CQ message

    /// Without any modifier set, index 0 is "CQ <CALL> <GRID>".
    func test_generateMessages_index0_noModifier_containsCallAndGrid() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertEqual(messages[0], "CQ EA4IQL IN76")
    }

    /// When cqModifier = "DX", index 0 becomes "CQ DX <CALL> <GRID>".
    func test_generateMessages_index0_dxModifier_includesModifier() {
        UserDefaults.standard.set("DX", forKey: "cqModifier")
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertTrue(messages[0].hasPrefix("CQ DX "),
                      "Expected 'CQ DX …', got '\(messages[0])'")
    }

    /// When cqModifier = "POTA", the modifier must appear in the CQ message.
    func test_generateMessages_index0_potaModifier_includesModifier() {
        UserDefaults.standard.set("POTA", forKey: "cqModifier")
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertTrue(messages[0].hasPrefix("CQ POTA "),
                      "Expected 'CQ POTA …', got '\(messages[0])'")
    }

    /// When cqModifier = "NONE", no modifier token appears in the CQ message.
    func test_generateMessages_index0_noneModifier_isOmitted() {
        UserDefaults.standard.set("NONE", forKey: "cqModifier")
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        // Should be "CQ EA4IQL IN76" — no extra token between CQ and callsign
        let parts = messages[0].split(separator: " ").map(String.init)
        XCTAssertEqual(parts[0], "CQ")
        XCTAssertEqual(parts[1], callsign.uppercased())
    }

    /// When `includeGrid = false`, the grid is omitted from the CQ message.
    func test_generateMessages_index0_includeGridFalse_omitsGrid() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr,
            includeGrid: false
        )
        XCTAssertFalse(messages[0].contains(locator),
                       "Grid '\(locator)' should not appear when includeGrid is false")
        XCTAssertEqual(messages[0], "CQ EA4IQL")
    }

    /// "OTHER" modifier resolves the actual value from `cqModifierOther`.
    func test_generateMessages_index0_otherModifierResolvesFromUserDefaults() {
        UserDefaults.standard.set("OTHER", forKey: "cqModifier")
        UserDefaults.standard.set("SOTA",  forKey: "cqModifierOther")
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertTrue(messages[0].hasPrefix("CQ SOTA "),
                      "Expected 'CQ SOTA …', got '\(messages[0])'")
    }

    /// "OTHER" with an empty cqModifierOther falls back to no modifier.
    func test_generateMessages_index0_otherModifierEmpty_isOmitted() {
        UserDefaults.standard.set("OTHER", forKey: "cqModifier")
        UserDefaults.standard.set("",      forKey: "cqModifierOther")
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        // Should not have a dangling modifier token
        XCTAssertTrue(messages[0].hasPrefix("CQ \(callsign.uppercased())"),
                      "Expected no modifier, got '\(messages[0])'")
    }

    // MARK: - Index-1: Grid reply

    /// Index 1 is the reply with my grid: "DX DE MYCALL MYGRID".
    func test_generateMessages_index1_containsDxCallAndMyGrid() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertTrue(messages[1].contains(dxCall.uppercased()))
        XCTAssertTrue(messages[1].contains(callsign.uppercased()))
        XCTAssertTrue(messages[1].contains(String(locator.prefix(4)).uppercased()))
    }

    // MARK: - Index-2: Signal report

    /// Index 2 is the signal report: "DX DE MYCALL +05".
    func test_generateMessages_index2_containsPositiveReport() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: 5.0
        )
        XCTAssertTrue(messages[2].hasSuffix("+05"),
                      "Expected '+05' suffix, got '\(messages[2])'")
    }

    /// SNR of -14 formats as "-14".
    func test_generateMessages_index2_negativeReport_formatsCorrectly() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: -14.0
        )
        XCTAssertTrue(messages[2].hasSuffix("-14"),
                      "Expected '-14' suffix, got '\(messages[2])'")
    }

    /// SNR above +30 is clamped to +30.
    func test_generateMessages_index2_snrAboveCeiling_clampedToPlus30() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: 35.0
        )
        XCTAssertTrue(messages[2].hasSuffix("+30"),
                      "Expected clamped '+30', got '\(messages[2])'")
    }

    /// SNR below -30 is clamped to -30.
    func test_generateMessages_index2_snrBelowFloor_clampedToMinus30() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: -40.0
        )
        XCTAssertTrue(messages[2].hasSuffix("-30"),
                      "Expected clamped '-30', got '\(messages[2])'")
    }

    // MARK: - Index-3: R-report

    /// Index 3 is the R-report: "DX DE MYCALL R+05".
    func test_generateMessages_index3_containsRAcknowledgedReport() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: 5.0
        )
        XCTAssertTrue(messages[3].hasSuffix("R+05"),
                      "Expected 'R+05' suffix, got '\(messages[3])'")
    }

    // MARK: - Index-4/5/6: Protocol closers

    func test_generateMessages_index4_containsRRR() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertTrue(messages[4].hasSuffix("RRR"))
    }

    func test_generateMessages_index5_containsFinal73() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertTrue(messages[5].hasSuffix("73"))
    }

    func test_generateMessages_index6_containsRR73() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: dxCall, dxLocator: dxLocator,
            snrToSend: snr
        )
        XCTAssertTrue(messages[6].hasSuffix("RR73"))
    }

    // MARK: - Empty DX callsign

    /// When DX callsign is empty, messages 1–6 use the "XXXXXX" placeholder.
    func test_generateMessages_emptyDxCallsign_usesPlaceholder() {
        let messages = sut.generateMessages(
            callsign: callsign, locator: locator,
            dxCallsign: "", dxLocator: "",
            snrToSend: snr
        )
        // Messages at indices 1–6 should reference the placeholder
        for index in 1...6 {
            XCTAssertTrue(messages[index].contains("XXXXXX"),
                "Index \(index) expected 'XXXXXX' placeholder, got '\(messages[index])'")
        }
    }

    // MARK: - SOTA regression

    /// Regression: "CQ SOTA VE7ZAX CN88" is 19 chars and must not be truncated.
    func test_generateMessages_index0_sotaModifierWithFullGrid_notTruncated() {
        UserDefaults.standard.set("SOTA", forKey: "cqModifier")
        let messages = sut.generateMessages(
            callsign: "VE7ZAX", locator: "CN88",
            dxCallsign: "K1ABC", dxLocator: "FN20",
            snrToSend: snr
        )
        XCTAssertEqual(messages[0], "CQ SOTA VE7ZAX CN88")
    }
}
