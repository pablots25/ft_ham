// FT8MessageCycleAndTypeTests.swift
// ft8_hamTests
//
// Direct unit tests for:
//   • FT8Message.calculateCycle(from:mode:)
//   • FT8Message.detectMessageType(text:parts:)
//   • FT8Message.isForMe(participants:myCallsign:isTX:)
//   • FT8Message.extractSNR(parts:type:)
//
// All functions are pure/static — no @MainActor required.
// Cycle tests build a Date pinned to specific seconds-of-minute, avoiding wall-clock fragility.

import XCTest
@testable import ft8_ham

/// Tests for FT8Message static helpers: cycle detection, type detection, isForMe, and extractSNR.
final class FT8MessageCycleAndTypeTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a Date whose `second` component is exactly `second`.
    /// Uses Calendar.gregorian for reproducibility.
    private func date(atSecond second: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = second
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: comps)!
    }

    private func parts(_ text: String) -> [Substring] {
        text.uppercased().split(separator: " ")
    }

    // MARK: - calculateCycle — FT8 (15-second slots)

    // Slot index 0 → seconds 0–14 → even
    func test_calculateCycle_ft8_0s_isEven() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 0), mode: .ft8)
        XCTAssertEqual(cycle, .even)
    }

    func test_calculateCycle_ft8_14s_isEven() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 14), mode: .ft8)
        XCTAssertEqual(cycle, .even)
    }

    // Slot index 1 → seconds 15–29 → odd
    func test_calculateCycle_ft8_15s_isOdd() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 15), mode: .ft8)
        XCTAssertEqual(cycle, .odd)
    }

    func test_calculateCycle_ft8_29s_isOdd() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 29), mode: .ft8)
        XCTAssertEqual(cycle, .odd)
    }

    // Slot index 2 → seconds 30–44 → even
    func test_calculateCycle_ft8_30s_isEven() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 30), mode: .ft8)
        XCTAssertEqual(cycle, .even)
    }

    // Slot index 3 → seconds 45–59 → odd
    func test_calculateCycle_ft8_45s_isOdd() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 45), mode: .ft8)
        XCTAssertEqual(cycle, .odd)
    }

    func test_calculateCycle_ft8_59s_isOdd() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 59), mode: .ft8)
        XCTAssertEqual(cycle, .odd)
    }

    // MARK: - calculateCycle — FT4 (7.5-second slots)

    // Slot index 0: seconds 0–6 (Int(0/7.5)=0, even)
    func test_calculateCycle_ft4_0s_isEven() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 0), mode: .ft4)
        XCTAssertEqual(cycle, .even)
    }

    // Slot index 1: seconds 7 (Int(7/7.5)=0 rounded down=0? let's verify: Int(7.0/7.5)=0 → even)
    // Actually Int(Double(7) / 7.5) = Int(0.9333) = 0 → even
    // Slot index 1 starts at second 7.5: Int(Double(8)/7.5) = Int(1.066) = 1 → odd
    func test_calculateCycle_ft4_8s_isOdd() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 8), mode: .ft4)
        XCTAssertEqual(cycle, .odd)
    }

    // Slot index 2: second 15 → Int(15/7.5)=2 → even
    func test_calculateCycle_ft4_15s_isEven() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 15), mode: .ft4)
        XCTAssertEqual(cycle, .even)
    }

    // Slot index 3: second 23 → Int(23/7.5)=3 → odd
    func test_calculateCycle_ft4_23s_isOdd() {
        let cycle = FT8Message.calculateCycle(from: date(atSecond: 23), mode: .ft4)
        XCTAssertEqual(cycle, .odd)
    }

    // MARK: - detectMessageType

    func test_detectMessageType_cq_returnsOk() {
        let text = "CQ EA4IQL IN76"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .cq)
    }

    func test_detectMessageType_cqWithModifier_returnsCq() {
        let text = "CQ DX EA4IQL IN76"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .cq)
    }

    func test_detectMessageType_gridExchange_returnsGridExchange() {
        let text = "K1ABC EA4IQL IN76"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .gridExchange)
    }

    func test_detectMessageType_standardReport_returnsStandardSignalReport() {
        let text = "K1ABC EA4IQL +05"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .standardSignalReport)
    }

    func test_detectMessageType_rReport_returnsRSignalReport() {
        let text = "K1ABC EA4IQL R+05"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .rSignalReport)
    }

    func test_detectMessageType_rr73_returnsRR73() {
        let text = "K1ABC EA4IQL RR73"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .rr73)
    }

    func test_detectMessageType_rrr_returnsRRR() {
        let text = "K1ABC EA4IQL RRR"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .rrr)
    }

    func test_detectMessageType_73_returnsFinal73() {
        let text = "K1ABC EA4IQL 73"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .final73)
    }

    func test_detectMessageType_unknownGarbage_returnsUnknown() {
        let text = "NOTHING USEFUL HERE"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .unknown)
    }

    func test_detectMessageType_emptyString_returnsUnknown() {
        XCTAssertEqual(FT8Message.detectMessageType(text: "", parts: []), .unknown)
    }

    func test_detectMessageType_internalTimestamp_returnsInternalTimestamp() {
        // Format: "yyyy-MM-dd HH:mm:ss - BAND"
        let text = "2026-01-03 12:00:00 - 20m"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .internalTimestamp)
    }

    func test_detectMessageType_negativeSignalReport_returnsStandardSignalReport() {
        let text = "K1ABC EA4IQL -14"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .standardSignalReport)
    }

    func test_detectMessageType_rNegativeReport_returnsRSignalReport() {
        let text = "K1ABC EA4IQL R-08"
        XCTAssertEqual(FT8Message.detectMessageType(text: text, parts: parts(text)), .rSignalReport)
    }

    // MARK: - isForMe

    private func makeParticipants(
        sender: String?,
        senderLocator: String? = nil,
        receiver: String?,
        receiverLocator: String? = nil
    ) -> (
        senderCallsign: String?,
        senderLocator: String?,
        receiverCallsign: String?,
        receiverLocator: String?
    ) {
        (sender, senderLocator, receiver, receiverLocator)
    }

    func test_isForMe_receiverMatchesMyCallsign_returnsTrue() {
        let p = makeParticipants(sender: "K1ABC", receiver: "EA4IQL")
        XCTAssertTrue(FT8Message.isForMe(participants: p, myCallsign: "EA4IQL", isTX: false))
    }

    func test_isForMe_senderMatchesMyCallsign_returnsTrue() {
        // My own TX messages: sender == my callsign
        let p = makeParticipants(sender: "EA4IQL", receiver: "K1ABC")
        XCTAssertTrue(FT8Message.isForMe(participants: p, myCallsign: "EA4IQL", isTX: true))
    }

    func test_isForMe_neitherMatches_returnsFalse() {
        let p = makeParticipants(sender: "W9XYZ", receiver: "VE3ABC")
        XCTAssertFalse(FT8Message.isForMe(participants: p, myCallsign: "EA4IQL", isTX: false))
    }

    func test_isForMe_cqMessageNoReceiver_notForMe() {
        // CQ messages have no receiverCallsign; they aren't "for me" unless my callsign is the sender
        let p = makeParticipants(sender: "K1ABC", receiver: nil)
        XCTAssertFalse(FT8Message.isForMe(participants: p, myCallsign: "EA4IQL", isTX: false))
    }

    func test_isForMe_cqSentByMe_returnsTrue() {
        let p = makeParticipants(sender: "EA4IQL", receiver: nil)
        XCTAssertTrue(FT8Message.isForMe(participants: p, myCallsign: "EA4IQL", isTX: false))
    }

    func test_isForMe_emptyMyCallsign_returnsFalse() {
        let p = makeParticipants(sender: "K1ABC", receiver: "EA4IQL")
        // An empty myCallsign can never match
        XCTAssertFalse(FT8Message.isForMe(participants: p, myCallsign: "", isTX: false))
    }

    func test_isForMe_caseInsensitive_returnsTrue() {
        let p = makeParticipants(sender: nil, receiver: "ea4iql")
        XCTAssertTrue(FT8Message.isForMe(participants: p, myCallsign: "EA4IQL", isTX: false))
    }

    // MARK: - extractSNR

    func test_extractSNR_positiveReport_returnsCorrectValue() {
        let p = parts("K1ABC EA4IQL +12")
        let snr = FT8Message.extractSNR(parts: p, type: .standardSignalReport)
        XCTAssertEqual(snr, 12.0)
    }

    func test_extractSNR_negativeReport_returnsCorrectValue() {
        let p = parts("K1ABC EA4IQL -08")
        let snr = FT8Message.extractSNR(parts: p, type: .standardSignalReport)
        XCTAssertEqual(snr, -8.0)
    }

    func test_extractSNR_rPlusReport_returnsCorrectValue() {
        let p = parts("K1ABC EA4IQL R+05")
        let snr = FT8Message.extractSNR(parts: p, type: .rSignalReport)
        XCTAssertEqual(snr, 5.0)
    }

    func test_extractSNR_rMinusReport_returnsCorrectValue() {
        let p = parts("K1ABC EA4IQL R-14")
        let snr = FT8Message.extractSNR(parts: p, type: .rSignalReport)
        XCTAssertEqual(snr, -14.0)
    }

    func test_extractSNR_cqType_returnsNaN() {
        let p = parts("CQ EA4IQL IN76")
        let snr = FT8Message.extractSNR(parts: p, type: .cq)
        XCTAssertTrue(snr.isNaN, "CQ messages carry no SNR; expected NaN, got \(snr)")
    }

    func test_extractSNR_internalTimestamp_returnsNaN() {
        let p = parts("2026-01-03 12:00:00 - 20m")
        let snr = FT8Message.extractSNR(parts: p, type: .internalTimestamp)
        XCTAssertTrue(snr.isNaN)
    }

    func test_extractSNR_rr73_returnsNaN() {
        // RR73 messages carry no numeric SNR token
        let p = parts("K1ABC EA4IQL RR73")
        let snr = FT8Message.extractSNR(parts: p, type: .rr73)
        XCTAssertTrue(snr.isNaN, "RR73 has no SNR; expected NaN")
    }

    func test_extractSNR_emptyParts_returnsNaN() {
        let snr = FT8Message.extractSNR(parts: [], type: .unknown)
        XCTAssertTrue(snr.isNaN)
    }

    func test_extractSNR_zeroBoundary_returnsZero() {
        let p = parts("K1ABC EA4IQL +00")
        let snr = FT8Message.extractSNR(parts: p, type: .standardSignalReport)
        XCTAssertEqual(snr, 0.0)
    }
}
