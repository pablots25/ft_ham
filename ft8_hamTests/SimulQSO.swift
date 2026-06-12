//
//  SimulQSO.swift
//  ft_hamTests
//

import XCTest
@testable import ft8_ham

@MainActor
final class SimulQSO: XCTestCase {

    var viewModel: FT8ViewModel!
    
    override func setUp() async throws {
        viewModel = FT8ViewModel()
        viewModel.autoSequencingEnabled = true
        viewModel.autoCQReplyEnabled  = true
        viewModel.callsign = "EA1ABC"
        viewModel.locator = "IM99"
        viewModel.isFT4 = false
        viewModel.selectedBand = .band20m
    }

    override func tearDown() async throws {
        viewModel = nil
    }

    @MainActor
    func testSimulatedQSO_StateMachineOnly() async {

        let manager = QSOStatusManager()
        let myCallsign = "EA1ABC"

        // 1️⃣ RX CQ
        let cq = FT8Message(
            text: "CQ EA2ABC FN31",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: 12,
            frequency: 14074000,
            band: .band20m
        )

        let action1 = manager.startReply(
            to: cq,
            myCallsign: myCallsign,
            myLocator: "IM99"
        )

        XCTAssertEqual(action1, .sendGrid(dxCallsign: "EA2ABC", dxLocator: "FN31"))
        XCTAssertEqual(manager.qsoState, .sendingGrid(dxCallsign: "EA2ABC"))
        XCTAssertEqual(manager.lockedDXCallsign, "EA2ABC")

        // 2️⃣ RX signal report
        let report = FT8Message(
            text: "EA1ABC EA2ABC -10",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        let action2 = manager.handleIncomingMessage(
            report,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action2, .sendRReport(dxCallsign: "EA2ABC", report: 12))
        XCTAssertEqual(manager.qsoState, .sendingRReport(dxCallsign: "EA2ABC"))

        // 3️⃣ RX RRR
        let rrr = FT8Message(
            text: "EA1ABC EA2ABC RRR",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        let action3 = manager.handleIncomingMessage(
            rrr,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action3, .sendRR73(dxCallsign: "EA2ABC"))
        XCTAssertEqual(manager.qsoState, .sending73(dxCallsign: "EA2ABC"))

        // 4️⃣ RX final 73
        let final73 = FT8Message(
            text: "EA1ABC EA2ABC 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        let action4 = manager.handleIncomingMessage(
            final73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action4, .completeQSO(dxCallsign: "EA2ABC"))
        // Note: closeQSO resets state to .idle for operational readiness
        XCTAssertEqual(manager.qsoState, .idle)
    }



    @MainActor
    func testStandardFT8_QSO_RSignalPath() async {
        // RUN MODE: We receive grid (someone responding to our CQ), we send report,
        // they send R-report, we send RRR, they send RR73/73

        let manager = QSOStatusManager()
        let myCallsign = "EA1ABC"

        // 1️⃣ RX Grid (someone responding to our CQ)
        let grid = FT8Message(
            text: "EA1ABC EA2ABC FN31",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        let action1 = manager.handleIncomingMessage(
            grid,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action1, .sendReport(dxCallsign: "EA2ABC", report: -10))
        XCTAssertEqual(manager.qsoState, .sendingReport(dxCallsign: "EA2ABC"))

        // 2️⃣ RX R-15 (DX confirms our report with R-report)
        // In RUN mode, we should respond with RRR (not RR73)
        let rSignal = FT8Message(
            text: "EA1ABC EA2ABC R-15",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -15,
            frequency: 14074000,
            band: .band20m
        )

        let action2 = manager.handleIncomingMessage(
            rSignal,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // RUN mode: receiving R-report sends RR73 (combines ack + 73)
        XCTAssertEqual(action2, .sendRR73(dxCallsign: "EA2ABC"))
        XCTAssertEqual(manager.qsoState, .sending73(dxCallsign: "EA2ABC"))

        // 3️⃣ RX RR73 or 73 from DX - since we're in sending73, this closes QSO
        let rr73 = FT8Message(
            text: "EA1ABC EA2ABC RR73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -15,
            frequency: 14074000,
            band: .band20m
        )

        let action3 = manager.handleIncomingMessage(
            rr73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // RR73 received in sending73 state sends courtesy 73
        XCTAssertEqual(action3, .send73(dxCallsign: "EA2ABC"))
        XCTAssertEqual(manager.qsoState, .sending73(dxCallsign: "EA2ABC"))
    }

    
    func testIgnoreCQWhenAutoCQReplyDisabled() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()
        viewModel.autoCQReplyEnabled = false
        
        let cqMessage = FT8Message(
            text: "CQ EA3XYZ JN11",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: 5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = viewModel.qsoManager.handleIncomingMessage(
            cqMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )
        
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
        XCTAssertEqual(viewModel.qsoManager.lockedDXCallsign, "")
    }
    
    func testReplyToCQ() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()
        viewModel.autoCQReplyEnabled = false
        
        let cqMessage = FT8Message(
            text: "CQ EA3XYZ JN11",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: 5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = viewModel.qsoManager.startReply(
            to: cqMessage,
            myCallsign: myCallsign,
            myLocator: "IM99"
        )
        
        XCTAssertEqual(action, .sendGrid(dxCallsign: "EA3XYZ", dxLocator: "JN11"))
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingGrid(dxCallsign: "EA3XYZ"))
        XCTAssertEqual(viewModel.qsoManager.lockedDXCallsign, "EA3XYZ")
    }

    func testIgnoreRRRWithoutActiveQSO() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()
        
        let strayRRR = FT8Message(
            text: "EA1ABC EA9AAA RRR",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -20,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = viewModel.qsoManager.handleIncomingMessage(
            strayRRR,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
    }
    
    func testDuplicateSignalReportDoesNotAdvanceState() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()
        
        let gridMessage = FT8Message(
            text: "EA1ABC EA2ABC FN31",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -12,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = viewModel.qsoManager.handleIncomingMessage(
            gridMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        XCTAssertEqual(action, .sendReport(dxCallsign: "EA2ABC", report: -12))
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingReport(dxCallsign: "EA2ABC"))
        
        let duplicateGridMessage = gridMessage
        
        let action1 = viewModel.qsoManager.handleIncomingMessage(
            duplicateGridMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        // Duplicate message should be ignored
        XCTAssertEqual(action1, .ignore, "Duplicate message should be ignored")
        // State should remain unchanged
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingReport(dxCallsign: "EA2ABC"))
    }
    
    func testIgnoreOtherDXDuringActiveQSO() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()
        
        let firstDX = FT8Message(
            text: "EA1ABC EA2ABC FN31",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -8,
            frequency: 14074000,
            band: .band20m
        )
        
        viewModel.qsoManager.lastReceivedSNR = -8
        
        _ = viewModel.qsoManager.handleIncomingMessage(
            firstDX,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        let intruderDX = FT8Message(
            text: "EA1ABC EA7ZZZ IM76",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = viewModel.qsoManager.handleIncomingMessage(
            intruderDX,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(viewModel.qsoManager.lockedDXCallsign, "EA2ABC")
    }

    func testReceiveRR73CompletesQSO() async {
        // RUN MODE: After sending RRR, receive RR73 to complete
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()

        let rr73Message = FT8Message(
            text: "EA1ABC EA2ABC RR73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -12,
            frequency: 14074000,
            band: .band20m
        )

        viewModel.qsoManager.lockedDXCallsign = "EA2ABC"
        viewModel.qsoManager.qsoState = .sendingRRR(dxCallsign: "EA2ABC")

        let action = viewModel.qsoManager.handleIncomingMessage(
            rr73Message,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // RR73 in sendingRRR state sends courtesy 73 and transitions to sending73
        XCTAssertEqual(action, .send73(dxCallsign: "EA2ABC"))
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sending73(dxCallsign: "EA2ABC"))
    }
    
    func testReceive73AfterRRRCompletesQSO() async {
        // S&P MODE: After sending RR73, receive courtesy 73 from DX
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()

        let final73Message = FT8Message(
            text: "EA1ABC EA2ABC 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        viewModel.qsoManager.lockedDXCallsign = "EA2ABC"
        viewModel.qsoManager.qsoState = .sending73(dxCallsign: "EA2ABC")

        let action = viewModel.qsoManager.handleIncomingMessage(
            final73Message,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action, .completeQSO(dxCallsign: "EA2ABC"))
        // Note: closeQSO resets state to .idle for operational readiness
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
    }

    @MainActor
    func testRX73AfterRRR_ClosesQSO() async {
        // S&P MODE: After sending RR73, receive courtesy 73 from DX

        let manager = QSOStatusManager()
        let myCallsign = "EA1ABC"

        manager.lockedDXCallsign = "EA2ABC"
        manager.qsoState = .sending73(dxCallsign: "EA2ABC")

        let final73 = FT8Message(
            text: "EA1ABC EA2ABC 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -9,
            frequency: 14074000,
            band: .band20m
        )

        let action = manager.handleIncomingMessage(
            final73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action, .completeQSO(dxCallsign: "EA2ABC"))
        // Note: closeQSO resets state to .idle for operational readiness
        XCTAssertEqual(manager.qsoState, .idle)
    }




    func testFT4StandardQSOFlow() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()
        viewModel.isFT4 = true
        
        let gridMessage = FT8Message(
            text: "EA1ABC EA2ABC IN52",
            mode: .ft4,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -6,
            frequency: 7049000,
            band: .band40m
        )
        
        viewModel.qsoManager.lastReceivedSNR = -6
        
        let action = viewModel.qsoManager.handleIncomingMessage(
            gridMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        XCTAssertEqual(action, .sendReport(dxCallsign: "EA2ABC", report: -6))
    }

}

@MainActor
final class SimulQSO2: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        viewModel = FT8ViewModel()
        viewModel.autoSequencingEnabled = true
        viewModel.autoCQReplyEnabled  = true
        viewModel.callsign = "EA1ABC"
        viewModel.locator = "IM99"
        viewModel.isFT4 = false
        viewModel.selectedBand = .band20m
    }

    override func tearDown() async throws {
        viewModel = nil
    }

    func testSimulatedQSOWithStateValidation() async {
        let myCallsign = "EA1ABC"
        viewModel.qsoList.removeAll()


        // 1️⃣ CQ recibido
        let cqMessage = FT8Message(
            text: "CQ EA2ABC FN31",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: 12,
            frequency: 14074000,
            band: .band20m
        )

        let action1 = viewModel.qsoManager.startReply(
            to: cqMessage,
            myCallsign: myCallsign,
            myLocator: "IM99"
        )

        XCTAssertEqual(action1, .sendGrid(dxCallsign: "EA2ABC", dxLocator: "FN31"))
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingGrid(dxCallsign: "EA2ABC"))

        // 2️⃣ Reporte recibido
        let reportMessage = FT8Message(
            text: "EA1ABC EA2ABC -10",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        let action2 = viewModel.qsoManager.handleIncomingMessage(
            reportMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action2, .sendRReport(dxCallsign: "EA2ABC", report: 12))

        // 3️⃣ RRR recibido
        let rrrMessage = FT8Message(
            text: "EA1ABC EA2ABC RRR",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        let action3 = viewModel.qsoManager.handleIncomingMessage(
            rrrMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action3, .sendRR73(dxCallsign: "EA2ABC"))

        // 4️⃣ 73 final recibido → cortesía
        let final73Message = FT8Message(
            text: "EA1ABC EA2ABC 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -10,
            frequency: 14074000,
            band: .band20m
        )

        let action4 = viewModel.qsoManager.handleIncomingMessage(
            final73Message,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // Note: closeQSO resets state to .idle for operational readiness
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
        XCTAssertEqual(action4, .completeQSO(dxCallsign: "EA2ABC"))

    }

    func testIgnoreCQWhenAutoCQReplyDisabled() async {
        viewModel.resetQSOState()
        viewModel.autoCQReplyEnabled = false

        let cq = FT8Message(
            text: "CQ EA3XYZ JN11",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: 5,
            frequency: 14074000,
            band: .band20m
        )

        let action = viewModel.qsoManager.handleIncomingMessage(
            cq,
            myCallsign: "EA1ABC",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )

        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
    }

    func testIgnoreRRRWithoutActiveQSO() async {
        viewModel.resetQSOState()

        let stray = FT8Message(
            text: "EA1ABC EA9AAA RRR",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -20,
            frequency: 14074000,
            band: .band20m
        )

        let action = viewModel.qsoManager.handleIncomingMessage(
            stray,
            myCallsign: "EA1ABC",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
    }

    func testFT4StandardQSOFlow() async {
        viewModel.resetQSOState()
        viewModel.isFT4 = true

        let gridMessage = FT8Message(
            text: "EA1ABC EA2ABC IN52",
            mode: .ft4,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -6,
            frequency: 7049000,
            band: .band40m
        )

        let action = viewModel.qsoManager.handleIncomingMessage(
            gridMessage,
            myCallsign: "EA1ABC",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action, .sendReport(dxCallsign: "EA2ABC", report: -6))
    }
}

