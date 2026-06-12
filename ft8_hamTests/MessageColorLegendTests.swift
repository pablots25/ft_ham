//
//  MessageColorLegendTests.swift
//  ft8_hamTests
//
//  Regression tests ensuring that backgroundColor(for:) returns the correct
//  Color for every message type / state combination shown in the Color Legend.
//

import XCTest
import SwiftUI
@testable import ft8_ham

final class MessageColorLegendTests: XCTestCase {

    // Our local station callsign used throughout these tests.
    private let myCallsign = "EA1AAA"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(myCallsign, forKey: "callsign")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "callsign")
        super.tearDown()
    }

    // MARK: - Legend entry 1: Yellow — own CQ TX

    func test_backgroundColor_cqTX_isYellow() {
        let msg = FT8Message(
            text: "CQ \(myCallsign) IN76",
            mode: .ft8,
            isTX: true
        )
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertTrue(msg.isTX)
        XCTAssertEqual(backgroundColor(for: msg), Color.yellow.opacity(0.2))
    }

    // MARK: - Legend entry 2: Purple — received CQ from another station

    func test_backgroundColor_cqReceived_isPurple() {
        let msg = FT8Message(
            text: "CQ EA2BBB IN76",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .cq)
        XCTAssertFalse(msg.isTX)
        XCTAssertEqual(backgroundColor(for: msg), Color.purple.opacity(0.2))
    }

    // MARK: - Legend entry 3: Blue — grid exchange directed at me

    func test_backgroundColor_gridExchangeForMe_isBlue() {
        // Format: <receiver> <sender> <grid> — receiver is our callsign
        let msg = FT8Message(
            text: "\(myCallsign) EA2BBB IN76",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .gridExchange)
        XCTAssertTrue(msg.forMe)
        XCTAssertEqual(backgroundColor(for: msg), Color.blue.opacity(0.2))
    }

    func test_backgroundColor_gridExchangeNotForMe_isSystemBackground() {
        let msg = FT8Message(
            text: "EA3CCC EA2BBB IN76",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .gridExchange)
        XCTAssertFalse(msg.forMe)
        XCTAssertEqual(backgroundColor(for: msg), Color(UIColor.systemBackground))
    }

    // MARK: - Legend entry 4: Orange — signal report directed at me

    func test_backgroundColor_signalReportForMe_isOrange() {
        let msg = FT8Message(
            text: "\(myCallsign) EA2BBB -07",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .standardSignalReport)
        XCTAssertTrue(msg.forMe)
        XCTAssertEqual(backgroundColor(for: msg), Color.orange.opacity(0.2))
    }

    func test_backgroundColor_rSignalReportForMe_isOrange() {
        let msg = FT8Message(
            text: "\(myCallsign) EA2BBB R-07",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .rSignalReport)
        XCTAssertTrue(msg.forMe)
        XCTAssertEqual(backgroundColor(for: msg), Color.orange.opacity(0.2))
    }

    func test_backgroundColor_signalReportNotForMe_isSystemBackground() {
        let msg = FT8Message(
            text: "EA3CCC EA2BBB -07",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .standardSignalReport)
        XCTAssertFalse(msg.forMe)
        XCTAssertEqual(backgroundColor(for: msg), Color(UIColor.systemBackground))
    }

    // MARK: - Legend entry 5: Purple — final exchange messages (RR73 / RRR / 73)

    func test_backgroundColor_rr73_isPurple() {
        let msg = FT8Message(
            text: "\(myCallsign) EA2BBB RR73",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .rr73)
        XCTAssertEqual(backgroundColor(for: msg), Color.purple.opacity(0.2))
    }

    func test_backgroundColor_rrr_isPurple() {
        let msg = FT8Message(
            text: "\(myCallsign) EA2BBB RRR",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .rrr)
        XCTAssertEqual(backgroundColor(for: msg), Color.purple.opacity(0.2))
    }

    func test_backgroundColor_final73_isPurple() {
        let msg = FT8Message(
            text: "\(myCallsign) EA2BBB 73",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .final73)
        XCTAssertEqual(backgroundColor(for: msg), Color.purple.opacity(0.2))
    }

    // MARK: - Legend entry 6: Gray — unknown message type

    func test_backgroundColor_unknown_isGray() {
        let msg = FT8Message(
            text: "INVALID GARBLED MESSAGE",
            mode: .ft8,
            isTX: false
        )
        XCTAssertEqual(msg.msgType, .unknown)
        XCTAssertEqual(backgroundColor(for: msg), Color.gray.opacity(0.2))
    }

    // MARK: - Legend entry 7: System background — internal timestamp

    func test_backgroundColor_internalTimestamp_isSystemBackground() {
        let timestamp = Date()
        let msg = FT8Message(text: "2026-04-05 12:00:00 - 20m", mode: .ft8, timestamp: timestamp)
        XCTAssertEqual(msg.msgType, .internalTimestamp)
        XCTAssertEqual(backgroundColor(for: msg), Color(UIColor.systemBackground))
    }
}
