//
//  RXFilterModeTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

final class RXFilterModeTests: XCTestCase {

    private let myCallsign = "EA4IQL"
    private var savedCallsign: String?

    override func setUp() {
        super.setUp()
        savedCallsign = UserDefaults.standard.string(forKey: "callsign")
        UserDefaults.standard.set(myCallsign, forKey: "callsign")
    }

    override func tearDown() {
        UserDefaults.standard.set(savedCallsign, forKey: "callsign")
        super.tearDown()
    }

    // MARK: - Cycling & storage

    func test_next_cyclesThroughAllFourModes() {
        XCTAssertEqual(RXFilterMode.all.next, .mine)
        XCTAssertEqual(RXFilterMode.mine.next, .mineAndCQ)
        XCTAssertEqual(RXFilterMode.mineAndCQ.next, .needed)
        XCTAssertEqual(RXFilterMode.needed.next, .all)
    }

    func test_legacyRawValuesAreStable() {
        // Persisted @AppStorage ints from older versions must keep meaning.
        XCTAssertEqual(RXFilterMode(storage: 0), .all)
        XCTAssertEqual(RXFilterMode(storage: 1), .mine)
        XCTAssertEqual(RXFilterMode(storage: 2), .mineAndCQ)
        XCTAssertEqual(RXFilterMode(storage: 3), .needed)
        XCTAssertEqual(RXFilterMode(storage: 99), .all)
    }

    // MARK: - apply

    private var fixtures: (cq: FT8Message, forMe: FT8Message, tx: FT8Message, other: FT8Message) {
        let cq = FT8Message(text: "CQ K1ABC FN42", mode: .ft8)
        let forMe = FT8Message(text: "\(myCallsign) K1ABC -10", mode: .ft8)
        let tx = FT8Message(text: "CQ \(myCallsign) IN80", mode: .ft8, isTX: true)
        let other = FT8Message(text: "W1AW K1ABC RR73", mode: .ft8)
        XCTAssertEqual(cq.msgType, .cq)
        XCTAssertTrue(forMe.forMe)
        XCTAssertFalse(other.forMe)
        return (cq, forMe, tx, other)
    }

    func test_apply_all_keepsEverything() {
        let f = fixtures
        let out = RXFilterMode.all.apply([f.cq, f.forMe, f.tx, f.other], isNeeded: { _ in false })
        XCTAssertEqual(out.count, 4)
    }

    func test_apply_mine_keepsForMeAndTXOnly() {
        let f = fixtures
        let out = RXFilterMode.mine.apply([f.cq, f.forMe, f.tx, f.other], isNeeded: { _ in true })
        XCTAssertEqual(out.map(\.id), [f.forMe.id, f.tx.id])
    }

    func test_apply_mineAndCQ_alsoKeepsCQ() {
        let f = fixtures
        let out = RXFilterMode.mineAndCQ.apply([f.cq, f.forMe, f.tx, f.other], isNeeded: { _ in false })
        XCTAssertEqual(out.map(\.id), [f.cq.id, f.forMe.id, f.tx.id])
    }

    func test_apply_needed_usesPredicateAndKeepsOwnRows() {
        let f = fixtures
        // Only the station-to-station row is "needed"; TX and for-me rows
        // survive regardless, the CQ does not.
        let out = RXFilterMode.needed.apply([f.cq, f.forMe, f.tx, f.other]) { $0.id == f.other.id }
        XCTAssertEqual(out.map(\.id), [f.forMe.id, f.tx.id, f.other.id])
    }

    func test_apply_needed_dropsTimestampRows() {
        let stamp = FT8Message(text: "12:00:00", mode: .ft8, timestamp: Date())
        XCTAssertEqual(stamp.msgType, .internalTimestamp)
        let out = RXFilterMode.needed.apply([stamp]) { _ in false }
        XCTAssertTrue(out.isEmpty)
    }
}
