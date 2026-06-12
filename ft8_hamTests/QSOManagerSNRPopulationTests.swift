//
//  QSOManagerSNRPopulationTests.swift
//  ft_hamTests
//
//  Tests to ensure correct SNR population for RX/TX and sequential QSOs
//

import XCTest
@testable import ft8_ham

@MainActor
final class QSOManagerSNRPopulationTests: XCTestCase {

    private var manager: QSOStatusManager!
    private let myCallsign = "EA1TST"
    private let myLocator = "IN70"

    override func setUp() {
        super.setUp()
        manager = QSOStatusManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    private func makeMessage(
        text: String,
        measuredSNR: Double,
        isTX: Bool = false,
        mode: FT8Message.FT8MessageMode = .ft8,
        band: FT8Message.Band = .band20m
    ) -> FT8Message {
        FT8Message(
            text: text,
            mode: mode,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: measuredSNR,
            frequency: 14_074_000,
            isTX: isTX,
            band: band
        )
    }

    func testSNRFrozenFromCQ_RX() {
        let cq = makeMessage(text: "CQ K1ABC FN20", measuredSNR: -12)

        let action = manager.startReply(
            to: cq,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        XCTAssertEqual(action, .sendGrid(dxCallsign: "K1ABC", dxLocator: "FN20"))
        XCTAssertEqual(manager.lastSentSNR, -12)
        XCTAssertEqual(manager.lastReceivedSNR, Int.min)
    }

    func testReceivedSNRFromDXReport_RX() {
        let cq = makeMessage(text: "CQ K1ABC FN20", measuredSNR: -10)
        _ = manager.startReply(to: cq, myCallsign: myCallsign, myLocator: myLocator)

        // Use the same format as existing working tests
        let report = makeMessage(
            text: "EA1TST K1ABC -07",
            measuredSNR: -3
        )

        let action = manager.handleIncomingMessage(
            report,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )

        XCTAssertEqual(action, .sendRReport(dxCallsign: "K1ABC", report: -10))
        XCTAssertEqual(manager.lastSentSNR, -10)
        XCTAssertEqual(manager.lastReceivedSNR, -7)
    }

    func testTXMessageDoesNotCorruptSNR() {
        let cq = makeMessage(text: "CQ K1ABC FN20", measuredSNR: -8)
        _ = manager.startReply(to: cq, myCallsign: myCallsign, myLocator: myLocator)

        let selfTX = makeMessage(
            text: "K1ABC EA1TST FN20",
            measuredSNR: -99,
            isTX: true
        )

        _ = manager.handleIncomingMessage(
            selfTX,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )

        XCTAssertEqual(manager.lastSentSNR, -8)
        XCTAssertEqual(manager.lastReceivedSNR, Int.min)
    }

    func testSNRResetsBetweenQueuedQSOs() {
        let cq1 = makeMessage(text: "CQ K1ABC FN20", measuredSNR: -5)
        _ = manager.startReply(to: cq1, myCallsign: myCallsign, myLocator: myLocator)

        let report1 = makeMessage(text: "EA1TST K1ABC -10", measuredSNR: -2)
        _ = manager.handleIncomingMessage(
            report1,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )

        XCTAssertEqual(manager.lastSentSNR, -5)
        XCTAssertEqual(manager.lastReceivedSNR, -10)

        manager.resetQSO()

        let cq2 = makeMessage(text: "CQ W5XYZ EM12", measuredSNR: -15)
        _ = manager.startReply(to: cq2, myCallsign: myCallsign, myLocator: myLocator)

        XCTAssertEqual(manager.lastSentSNR, -15)
        XCTAssertEqual(manager.lastReceivedSNR, Int.min)
        XCTAssertEqual(manager.lockedDXCallsign, "W5XYZ")
    }

    func testForeignCQDoesNotAffectSNRDuringQSO() {
        let cqMessage = makeMessage(text: "CQ EA1ABC IN83", measuredSNR: -12)
        _ = manager.startReply(to: cqMessage, myCallsign: "MY1ABC", myLocator: "IN80")

        let foreignCQ = makeMessage(text: "CQ K1ZZ FN42", measuredSNR: -2)

        let action = manager.handleIncomingMessage(
            foreignCQ,
            myCallsign: "MY1ABC",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(manager.lastSentSNR, -12)
    }

}
