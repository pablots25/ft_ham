//
//  PileupSelectorTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

final class PileupSelectorTests: XCTestCase {

    private let me = "EA4IQL"

    private func caller(_ call: String, grid: String = "FN42") -> FT8Message {
        FT8Message(text: "\(me) \(call) \(grid)", mode: .ft8)
    }

    private func batch() -> (msgs: [FT8Message], a: FT8Message, b: FT8Message, c: FT8Message) {
        let cq = FT8Message(text: "CQ W1AW FN31", mode: .ft8)
        let a = caller("K1ABC"), b = caller("DL1XYZ", grid: "JO62"), c = caller("JA1QRP", grid: "PM95")
        let other = FT8Message(text: "W1AW K9XYZ EN52", mode: .ft8)   // grid to someone else
        let dupA = FT8Message(text: "\(me) K1ABC FN42", mode: .ft8)  // same caller, second tone
        return ([cq, a, other, b, dupA, c], a, b, c)
    }

    // MARK: - candidates

    func test_candidates_onlyStationsAnsweringMe_dedupedByCallsign() {
        let (msgs, a, b, c) = batch()
        let found = PileupSelector.candidates(in: msgs, myCallsign: me)
        XCTAssertEqual(found.map(\.callsign), [a.callsign, b.callsign, c.callsign])
    }

    func test_candidates_acceptsReportSkippingGrid() {
        let report = FT8Message(text: "\(me) K1ABC -05", mode: .ft8)
        XCTAssertEqual(report.msgType, .standardSignalReport)
        XCTAssertEqual(PileupSelector.candidates(in: [report], myCallsign: me).count, 1)
    }

    func test_candidates_ignoresOwnTXAndEmptyCallsign() {
        let tx = FT8Message(text: "K1ABC \(me) IN80", mode: .ft8, isTX: true)
        XCTAssertTrue(PileupSelector.candidates(in: [tx], myCallsign: me).isEmpty)
        XCTAssertTrue(PileupSelector.candidates(in: [caller("K1ABC")], myCallsign: "").isEmpty)
    }

    // MARK: - prioritize

    func test_prioritize_singleCaller_leavesOrderUntouched() {
        let cq = FT8Message(text: "CQ W1AW FN31", mode: .ft8)
        let a = caller("K1ABC")
        var selector = PileupSelector(preferNeverWorked: true, rng: SeededRandomNumberGenerator(seed: 1))
        let result = selector.prioritize([cq, a], myCallsign: me, workedCallsigns: [])
        XCTAssertEqual(result.messages.map(\.id), [cq.id, a.id])
        XCTAssertEqual(result.chosen?.id, a.id)
        XCTAssertEqual(result.pileupSize, 1)
    }

    func test_prioritize_isDeterministicForASeed_andMovesChosenToFront() {
        let (msgs, _, _, _) = batch()
        var s1 = PileupSelector(preferNeverWorked: false, rng: SeededRandomNumberGenerator(seed: 42))
        var s2 = PileupSelector(preferNeverWorked: false, rng: SeededRandomNumberGenerator(seed: 42))
        let r1 = s1.prioritize(msgs, myCallsign: me, workedCallsigns: [])
        let r2 = s2.prioritize(msgs, myCallsign: me, workedCallsigns: [])

        XCTAssertEqual(r1.pileupSize, 3)
        XCTAssertEqual(r1.chosen?.id, r2.chosen?.id)
        XCTAssertEqual(r1.messages.first?.id, r1.chosen?.id)
        XCTAssertEqual(r1.messages.count, msgs.count)
        // Everything else keeps its relative order.
        let rest = r1.messages.dropFirst().map(\.id)
        XCTAssertEqual(rest, msgs.filter { $0.id != r1.chosen?.id }.map(\.id))
    }

    func test_prioritize_coversEveryCallerAcrossSeeds() {
        let (msgs, a, b, c) = batch()
        var picked = Set<String>()
        for seed in 1...40 {
            var s = PileupSelector(preferNeverWorked: false, rng: SeededRandomNumberGenerator(seed: UInt64(seed)))
            picked.insert(s.prioritize(msgs, myCallsign: me, workedCallsigns: []).chosen?.callsign ?? "")
        }
        XCTAssertEqual(picked, [a.callsign!, b.callsign!, c.callsign!])
    }

    func test_prioritize_preferNeverWorked_picksOnlyUnworked() {
        let (msgs, a, b, c) = batch()
        for seed in 1...20 {
            var s = PileupSelector(preferNeverWorked: true, rng: SeededRandomNumberGenerator(seed: UInt64(seed)))
            let r = s.prioritize(msgs, myCallsign: me, workedCallsigns: [a.callsign!, c.callsign!])
            XCTAssertEqual(r.chosen?.callsign, b.callsign, "seed \(seed)")
        }
    }

    func test_prioritize_preferNeverWorked_fallsBackWhenAllWorked() {
        let (msgs, a, b, c) = batch()
        var s = PileupSelector(preferNeverWorked: true, rng: SeededRandomNumberGenerator(seed: 7))
        let r = s.prioritize(msgs, myCallsign: me, workedCallsigns: [a.callsign!, b.callsign!, c.callsign!])
        XCTAssertNotNil(r.chosen)
        XCTAssertEqual(r.pileupSize, 3)
    }
}
