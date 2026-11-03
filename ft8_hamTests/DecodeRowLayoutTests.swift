//
//  DecodeRowLayoutTests.swift
//  ft8_hamTests
//
//  Row decisions for the decode lists: the active-QSO marker and the mode
//  suffix. Pure functions, no UI or audio.
//

import XCTest
@testable import ft8_ham

final class DecodeRowLayoutTests: XCTestCase {

    // MARK: - activeCallsign(from:)

    func test_activeCallsign_emptyMeansNoQSO() {
        XCTAssertNil(DecodeRowLayout.activeCallsign(from: ""))
        XCTAssertNil(DecodeRowLayout.activeCallsign(from: "   "))
    }

    func test_activeCallsign_isUppercased() {
        XCTAssertEqual(DecodeRowLayout.activeCallsign(from: "ub5ofg"), "UB5OFG")
    }

    // MARK: - isActiveQSO

    func test_isActiveQSO_falseWithoutLockedCallsign() {
        let msg = FT8Message(text: "EA4IQL UB5OFG -12", mode: .ft8)
        XCTAssertFalse(DecodeRowLayout.isActiveQSO(msg, activeCallsign: nil))
    }

    func test_isActiveQSO_matchesSender() {
        let msg = FT8Message(text: "EA4IQL UB5OFG -12", mode: .ft8)
        XCTAssertEqual(msg.callsign?.uppercased(), "UB5OFG")
        XCTAssertTrue(DecodeRowLayout.isActiveQSO(msg, activeCallsign: "UB5OFG"))
    }

    func test_isActiveQSO_matchesReceiver() {
        let msg = FT8Message(text: "UB5OFG EA4IQL R-10", mode: .ft8, isTX: true)
        XCTAssertEqual(msg.dxCallsign?.uppercased(), "UB5OFG")
        XCTAssertTrue(DecodeRowLayout.isActiveQSO(msg, activeCallsign: "UB5OFG"))
    }

    func test_isActiveQSO_lockedCallsignIsCaseInsensitive() {
        let msg = FT8Message(text: "EA4IQL UB5OFG -12", mode: .ft8)
        let active = DecodeRowLayout.activeCallsign(from: "ub5ofg")
        XCTAssertTrue(DecodeRowLayout.isActiveQSO(msg, activeCallsign: active))
    }

    func test_isActiveQSO_falseForOtherStations() {
        let msg = FT8Message(text: "K1ABC N0XYZ FN31", mode: .ft8)
        XCTAssertFalse(DecodeRowLayout.isActiveQSO(msg, activeCallsign: "UB5OFG"))
    }

    func test_isActiveQSO_falseForTimestampRows() {
        let msg = FT8Message(
            text: "2026-09-25 12:00:00 - 20m",
            mode: .ft8,
            timestamp: Date(),
            band: .band20m,
            msgType: .internalTimestamp
        )
        XCTAssertFalse(DecodeRowLayout.isActiveQSO(msg, activeCallsign: "UB5OFG"))
    }

    // MARK: - showsModeSuffix

    func test_modeSuffix_hiddenWhenModeMatchesCurrent() {
        let ft8 = FT8Message(text: "CQ EA4IQL IN80", mode: .ft8)
        let ft4 = FT8Message(text: "CQ EA4IQL IN80", mode: .ft4)
        XCTAssertFalse(DecodeRowLayout.showsModeSuffix(for: ft8, mode: .ft8))
        XCTAssertFalse(DecodeRowLayout.showsModeSuffix(for: ft4, mode: .ft4))
    }

    func test_modeSuffix_shownForCrossModeHistory() {
        let ft8 = FT8Message(text: "CQ EA4IQL IN80", mode: .ft8)
        let ft4 = FT8Message(text: "CQ EA4IQL IN80", mode: .ft4)
        XCTAssertTrue(DecodeRowLayout.showsModeSuffix(for: ft8, mode: .ft4))
        XCTAssertTrue(DecodeRowLayout.showsModeSuffix(for: ft4, mode: .ft8))
    }

    // MARK: - Column text

    func test_columnText_nanFallbacks() {
        let msg = FT8Message(text: "Partial data loss", mode: .ft8,
                             measuredSNR: .nan, frequency: .nan, timeOffset: .nan)
        XCTAssertEqual(DecodeRowLayout.snrText(msg), "0")
        XCTAssertEqual(DecodeRowLayout.frequencyText(msg), "0")
        XCTAssertEqual(DecodeRowLayout.timeOffsetText(msg), "0.00s")
    }

    func test_columnText_formatsValues() {
        let msg = FT8Message(text: "CQ EA4IQL IN80", mode: .ft8,
                             measuredSNR: -12, frequency: 1500.4, timeOffset: 0.1)
        XCTAssertEqual(DecodeRowLayout.snrText(msg), "-12")
        XCTAssertEqual(DecodeRowLayout.frequencyText(msg), "1500")
        XCTAssertEqual(DecodeRowLayout.timeOffsetText(msg), "0.10s")
    }
}
