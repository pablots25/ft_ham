//
//  FT8ViewModelLoggingIntegrationTests.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/1/26.
//


import XCTest
@testable import ft8_ham

@MainActor
final class FT8ViewModelLoggingIntegrationTests: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        viewModel = FT8ViewModel()
        viewModel.callsign = "EA1ABC"
        viewModel.locator = "IM99"
        viewModel.autoSequencingEnabled = true
        viewModel.autoCQReplyEnabled = true

        viewModel.qsoList.removeAll()
        viewModel.resetQSOState()
    }

    override func tearDown() async throws {
        viewModel = nil
    }

    func testCompletedQSO_IsLoggedInQSOList() async {

        let myCallsign = "EA1ABC"

        // 1️⃣ RX CQ
        let cq = FT8Message(
            text: "CQ EA2ABC FN31",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: 10,
            frequency: 14_074_000,
            band: .band20m
        )

        let action1 = viewModel.qsoManager.startReply(
            to: cq,
            myCallsign: myCallsign,
            myLocator: "IM99"
        )

        XCTAssertEqual(action1, .sendGrid(dxCallsign: "EA2ABC", dxLocator: "FN31"))

        viewModel.handleRXAction(action1)

        // 2️⃣ RX report
        let report = FT8Message(
            text: "EA1ABC EA2ABC -10",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -7,
            frequency: 14_074_000,
            band: .band20m
        )

        let action2 = viewModel.qsoManager.handleIncomingMessage(
            report,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action2, .sendRReport(dxCallsign: "EA2ABC", report: 10))
        viewModel.handleRXAction(action2)

        // 3️⃣ RX RRR
        let rrr = FT8Message(
            text: "EA1ABC EA2ABC RRR",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -8,
            frequency: 14_074_000,
            band: .band20m
        )

        let action3 = viewModel.qsoManager.handleIncomingMessage(
            rrr,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action3, .sendRR73(dxCallsign: "EA2ABC"))
        viewModel.handleRXAction(action3)

        // 4️⃣ RX final 73 → closeQSO
        let final73 = FT8Message(
            text: "EA1ABC EA2ABC 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -9,
            frequency: 14_074_000,
            band: .band20m
        )

        let action4 = viewModel.qsoManager.handleIncomingMessage(
            final73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action4, .completeQSO(dxCallsign: "EA2ABC"))

        viewModel.handleRXAction(action4)

        // 5️⃣ Assert: QSO saved
        XCTAssertEqual(viewModel.qsoList.count, 1)

        let qso = viewModel.qsoList.first!
        XCTAssertEqual(qso.callsign, "EA2ABC")
        XCTAssertEqual(qso.grid, "FN31")
        XCTAssertEqual(qso.rstSent, "10")
        XCTAssertEqual(qso.rstRcvd, "-10")
    }
}
