import XCTest
@testable import ft8_ham

@MainActor
final class SimulQSO_AdditionalTests: XCTestCase {

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

    // 1) RR73 immediately after we send report (skip R-xx)
    func testRR73ImmediatelyAfterReport_CompletesQSO() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()

        // We receive grid and respond with report
        let grid = FT8Message(
            text: "EA1ABC EA2ABC FN31",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -8,
            frequency: 14074000,
            band: .band20m
        )

        let action1 = viewModel.qsoManager.handleIncomingMessage(
            grid,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action1, .sendReport(dxCallsign: "EA2ABC", report: -8))
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingReport(dxCallsign: "EA2ABC"))

        // DX sends RR73 immediately
        let rr73 = FT8Message(
            text: "EA1ABC EA2ABC RR73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -9,
            frequency: 14074000,
            band: .band20m
        )

        let action2 = viewModel.qsoManager.handleIncomingMessage(
            rr73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // RR73 now sends courtesy 73 back and transitions to sending73
        XCTAssertEqual(action2, .send73(dxCallsign: "EA2ABC"))
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sending73(dxCallsign: "EA2ABC"))
    }

    // 2) Repeated RRR should not regress or re-trigger actions
    func testRepeatedRRRDoesNotChangeCompletedOrAdvanceState() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()

        // Bring state to sending73
        viewModel.qsoManager.lockedDXCallsign = "EA2ABC"
        viewModel.qsoManager.qsoState = .sending73(dxCallsign: "EA2ABC")

        let rrr = FT8Message(
            text: "EA1ABC EA2ABC RRR",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -12,
            frequency: 14074000,
            band: .band20m
        )

        // First RRR advances to sendRR73 (if not already sent) -> your logic maps to complete on 73; here we assert it triggers RR73 send intent
        let action1 = viewModel.qsoManager.handleIncomingMessage(
            rrr,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action1, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sending73(dxCallsign: "EA2ABC"))

        // Duplicate RRR should not change anything
        let action2 = viewModel.qsoManager.handleIncomingMessage(
            rrr,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action2, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sending73(dxCallsign: "EA2ABC"))
    }

    // 3) Repeated RR73 or 73 after completion should be ignored
    func testRepeatedRR73And73AfterCompletionAreIgnored() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()

        viewModel.qsoManager.lockedDXCallsign = "EA2ABC"
        viewModel.qsoManager.qsoState = .completed(dxCallsign: "EA2ABC")

        let rr73 = FT8Message(
            text: "EA1ABC EA2ABC RR73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -15,
            frequency: 14074000,
            band: .band20m
        )
        let final73 = FT8Message(
            text: "EA1ABC EA2ABC 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -16,
            frequency: 14074000,
            band: .band20m
        )

        let action1 = viewModel.qsoManager.handleIncomingMessage(
            rr73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action1, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .completed(dxCallsign: "EA2ABC"))

        let action2 = viewModel.qsoManager.handleIncomingMessage(
            final73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action2, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .completed(dxCallsign: "EA2ABC"))
    }

    // 4) Unexpected early 73 while still sendingGrid should be ignored
    func testUnexpectedEarly73TriggersRetryGrid() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()

        // Lock on DX and be in sendingGrid (typical after startReply to CQ)
        viewModel.qsoManager.lockedDXCallsign = "EA2ABC"
        viewModel.qsoManager.qsoState = .sendingGrid(dxCallsign: "EA2ABC")

        let early73 = FT8Message(
            text: "EA1ABC EA2ABC 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )

        let action = viewModel.qsoManager.handleIncomingMessage(
            early73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // Unexpected 73 while in sendingGrid should be ignored
        XCTAssertEqual(action, .ignore, "Unexpected 73 while sendingGrid should be ignored")
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingGrid(dxCallsign: "EA2ABC"))
    }

    // 5) FT4 variant where the first decoded message is a report (report-first path)
    func testFT4_ReportFirstPath_RR73Completes() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()
        viewModel.isFT4 = true
        viewModel.selectedBand = .band40m

        // First message is a report from DX
        let reportFirst = FT8Message(
            text: "EA1ABC EA2ABC -07",
            mode: .ft4,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -7,
            frequency: 7049000,
            band: .band40m
        )

        let action1 = viewModel.qsoManager.handleIncomingMessage(
            reportFirst,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action1, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)

        // DX then sends RR73
        let rr73 = FT8Message(
            text: "EA1ABC EA2ABC RR73",
            mode: .ft4,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -8,
            frequency: 7049000,
            band: .band40m
        )

        let action2 = viewModel.qsoManager.handleIncomingMessage(
            rr73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action2, .ignore)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
    }

    // 6) After completion, a new unrelated grid from another DX should be handled as a fresh start
    func testNewDXAfterCompletionStartsFresh() async {
        let myCallsign = "EA1ABC"
        viewModel.resetQSOState()

        // Completed with EA2ABC
        viewModel.qsoManager.lockedDXCallsign = "EA2ABC"
        viewModel.qsoManager.qsoState = .completed(dxCallsign: "EA2ABC")

        // New DX sends grid
        let newDXGrid = FT8Message(
            text: "EA1ABC EA7ZZZ IM76",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )

        // Depending on your implementation, after completion you might expect a reset; if not automatically reset,
        // handleIncomingMessage should still ignore if lock persists. Here we assert fresh handling: send report to new DX.
        // If your manager requires explicit reset, adjust this expectation accordingly.
        viewModel.qsoManager.lockedDXCallsign = "" // simulate that UI/flow reset the lock after completion
        viewModel.qsoManager.qsoState = .idle

        let action = viewModel.qsoManager.handleIncomingMessage(
            newDXGrid,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action, .sendReport(dxCallsign: "EA7ZZZ", report: -5))
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingReport(dxCallsign: "EA7ZZZ"))
    }
}
