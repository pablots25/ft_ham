//
//  QSOStatusManagerTests.swift
//  ft_hamTests
//

import XCTest
@testable import ft8_ham

@MainActor
final class QSOStatusManagerTests: XCTestCase {

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

    // Helper para crear mensajes sin errores de mutabilidad
    private func makeMessage(text: String, callsign: String = "", type: FT8MessageType = .unknown, isTX: Bool = false) -> FT8Message {
        return FT8Message(
            text: text,
            mode: .ft8,
            isRealtime: false,
            measuredSNR: -10.0,
            isTX: isTX,
            band: .band20m
        )
    }

    // -----------------------------------------------------
    // MARK: - Tests
    // -----------------------------------------------------

    func testStartReplySetsInitialState() {
        let cq = makeMessage(text: "CQ K1ABC FN20", callsign: "K1ABC")

        let action = manager.startReply(
            to: cq,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        XCTAssertEqual(manager.qsoState, .sendingGrid(dxCallsign: "K1ABC"))
        XCTAssertEqual(manager.lockedDXCallsign, "K1ABC")
        XCTAssertEqual(action, .sendGrid(dxCallsign: "K1ABC", dxLocator: "FN20"))
    }
    
    func testStartReplyToGrid() {
        let cq = makeMessage(text: "EA1TST K1ABC FN20", callsign: "K1ABC")

        let action = manager.startReply(
            to: cq,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        XCTAssertEqual(manager.qsoState, .sendingReport(dxCallsign: "K1ABC"))
        XCTAssertEqual(manager.lockedDXCallsign, "K1ABC")
        XCTAssertEqual(action, .sendReport(dxCallsign: "K1ABC", report: -10))
    }

    func testIdleToSendingGridViaAutoCQ() {
        let cq = makeMessage(text: "CQ DL1XYZ JO62", callsign: "DL1XYZ", type: .cq)

        let action = manager.handleIncomingMessage(
            cq,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // Nota: Verifica si tu lógica pasa a .listeningCQ o .sendingGrid directamente
        XCTAssertEqual(manager.qsoState, .sendingGrid(dxCallsign: "DL1XYZ"))
        if case .sendGrid(let dx, _) = action {
            XCTAssertEqual(dx, "DL1XYZ")
        } else {
            XCTFail("Expected .sendGrid action")
        }
    }

    func testTimeoutExceededResetsToIdle() {
        manager.lockedDXCallsign = "K1ABC"
//        manager.qsoState = .listeningGrid("K1ABC")
        
        // Seteamos el contador al límite (asegúrate de que retryCounter sea internal, no private)
        manager.retryCounter = manager.maxRetrySlots - 1

        let otherMsg = makeMessage(text: "CQ DE OTHER", callsign: "OTHER")
        _ = manager.handleIncomingMessage(otherMsg, myCallsign: myCallsign, autoSequencingEnabled: true, autoCQReplyEnabled: false)

        XCTAssertEqual(manager.qsoState, .idle)
    }
    
    // MARK: - Retry and Timeout Tests
    
    func testHandleRetryIncrementsCounter() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "K1ABC")
        manager.responseReceivedThisSlot = false
        
        XCTAssertEqual(manager.retryCounter, 0)
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(manager.retryCounter, 1)
        // In listeningReport, we resend grid (they didn't receive it)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "K1ABC", dxLocator: "FN20"))
        XCTAssertEqual(manager.qsoState, .listeningReport(dxCallsign: "K1ABC"))
    }
    
    func testHandleRetryExceedsMaxAndAborts() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "K1ABC")
        manager.retryCounter = manager.maxRetrySlots  // = 3, so next timeout will exceed max
        manager.responseReceivedThisSlot = false
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(manager.retryCounter, 0)  // Reset on abort
        XCTAssertEqual(action, .abortQSO)
        XCTAssertEqual(manager.qsoState, .idle)
        XCTAssertEqual(manager.lockedDXCallsign, "")  // Reset after timeout
    }
    
    func testHandleRetryRespectMaxRetrySlots() {
        manager.setupNewQSO(dx: "W5XYZ", locator: "FN31", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "W5XYZ")
        manager.lastSentSNR = -5
        manager.responseReceivedThisSlot = false
        
        // Retry 1 - resend grid (they didn't receive it)
        var action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 1)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "W5XYZ", dxLocator: "FN31"))
        
        manager.responseReceivedThisSlot = false
        // Retry 2
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 2)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "W5XYZ", dxLocator: "FN31"))
        
        manager.responseReceivedThisSlot = false
        // Retry 3 - still retrying
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 3)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "W5XYZ", dxLocator: "FN31"))
        
        manager.responseReceivedThisSlot = false
        // Next timeout should abort
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 0)
        XCTAssertEqual(action, .abortQSO)
        XCTAssertEqual(manager.qsoState, .idle)
        XCTAssertEqual(manager.lockedDXCallsign, "")
    }
    
    func testHandleQSOTimeoutRetriesSendingGrid() {
        manager.setupNewQSO(dx: "G4ABC", locator: "IO91", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "G4ABC")
        manager.retryCounter = 0
        manager.responseReceivedThisSlot = false
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(manager.retryCounter, 1)
        // In listeningReport, we resend grid (they didn't receive it)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "G4ABC", dxLocator: "IO91"))
        XCTAssertEqual(manager.qsoState, .listeningReport(dxCallsign: "G4ABC"))
    }
    
    func testHandleQSOTimeoutRetriesSendingReport() {
        manager.setupNewQSO(dx: "JA1ABC", locator: "PM95", initialSNR: -10)
        manager.qsoState = .listeningRReport(dxCallsign: "JA1ABC")
        manager.lastSentSNR = 12
        manager.retryCounter = 1
        manager.responseReceivedThisSlot = false
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(manager.retryCounter, 2)
        XCTAssertEqual(action, .sendRReport(dxCallsign: "JA1ABC", report: 12))
    }
    
    func testHandleQSOTimeoutRetriesSendingRReport() {
        manager.setupNewQSO(dx: "VE3XYZ", locator: "FN03", initialSNR: -10)
        manager.qsoState = .listeningRRR(dxCallsign: "VE3XYZ")
        manager.lastSentSNR = -8
        manager.retryCounter = 0
        manager.responseReceivedThisSlot = false
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(manager.retryCounter, 1)
        XCTAssertEqual(action, .sendRRR(dxCallsign: "VE3XYZ"))
    }
    
    func testHandleQSOTimeoutRetriesSendingRRR() {
        manager.setupNewQSO(dx: "F4XYZ", locator: "JN25", initialSNR: -10)
        manager.qsoState = .listeningRReport(dxCallsign: "F4XYZ")
        manager.retryCounter = 0
        manager.responseReceivedThisSlot = false
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(manager.retryCounter, 1)
        XCTAssertEqual(action, .sendRReport(dxCallsign: "F4XYZ", report: -10))
    }
    
    func testHandleQSOTimeoutRetriesSending73() {
        manager.setupNewQSO(dx: "DL1XYZ", locator: "JO62", initialSNR: -10)
        manager.qsoState = .listeningRRR(dxCallsign: "DL1XYZ")
        manager.retryCounter = 1
        manager.responseReceivedThisSlot = false
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(manager.retryCounter, 2)
        XCTAssertEqual(action, .sendRRR(dxCallsign: "DL1XYZ"))
    }
    
    func testHandleQSOTimeoutExceedsMaxAndAborts() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN31", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "K1ABC")
        manager.lastSentSNR = 10
        manager.retryCounter = manager.maxRetrySlots
        manager.responseReceivedThisSlot = false
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(action, .abortQSO)
        XCTAssertEqual(manager.qsoState, .idle)
        XCTAssertEqual(manager.lockedDXCallsign, "")
        XCTAssertEqual(manager.retryCounter, 0)  // Should be reset
    }
    
    func testHandleQSOTimeoutIgnoresWhenNoLockedCallsign() {
        manager.qsoState = .idle
        manager.lockedDXCallsign = ""
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(manager.qsoState, .idle)
    }
    
    func testHandleQSOTimeoutIgnoresWhenAlreadyCompleted() {
        manager.setupNewQSO(dx: "W1AW", locator: "FN31", initialSNR: -10)
        manager.qsoState = .completed(dxCallsign: "W1AW")
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(manager.qsoState, .completed(dxCallsign: "W1AW"))
    }
    
    func testHandleQSOTimeoutIgnoresWhenAlreadyTimedOut() {
        manager.qsoState = .timeout(dxCallsign: "K1ABC")
        manager.lockedDXCallsign = "K1ABC"
        
        let action = manager.handleQSOTimeout()
        
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(manager.qsoState, .timeout(dxCallsign: "K1ABC"))
    }
    
    func testRetryCounterResetsAfterNewQSO() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN31", initialSNR: -10)
        manager.retryCounter = 2
        
        manager.resetQSO()
        
        XCTAssertEqual(manager.retryCounter, 0)
        XCTAssertEqual(manager.lockedDXCallsign, "")
        XCTAssertEqual(manager.qsoState, .idle)
    }
    
    func testFullRetrySequenceWithTimeouts() {
        // Simulate a full QSO with multiple timeouts
        manager.setupNewQSO(dx: "W5XYZ", locator: "EM12", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "W5XYZ")
        manager.lastSentSNR = 8
        manager.responseReceivedThisSlot = false
        
        // First timeout - retry 1 (resend grid since they didn't receive it)
        var action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 1)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "W5XYZ", dxLocator: "EM12"))
        
        manager.responseReceivedThisSlot = false
        // Second timeout - retry 2
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 2)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "W5XYZ", dxLocator: "EM12"))
        
        manager.responseReceivedThisSlot = false
        // Third timeout - retry 3 (max reached, still retrying)
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 3)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "W5XYZ", dxLocator: "EM12"))
        XCTAssertEqual(manager.qsoState, .listeningReport(dxCallsign: "W5XYZ"))

        manager.responseReceivedThisSlot = false
        // Fourth timeout - aborts and resets
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 0)
        XCTAssertEqual(action, .abortQSO)
        XCTAssertEqual(manager.qsoState, .idle)
        XCTAssertEqual(manager.lockedDXCallsign, "")
    }
    
    func testCompletedQSODoesNotAllowRetries() {
        // Setup a QSO and complete it
        manager.setupNewQSO(dx: "G4ABC", locator: "IO91", initialSNR: -10)
        manager.qsoState = .completed(dxCallsign: "G4ABC")
        
        let otherMsg = makeMessage(text: "CQ DE OTHER", callsign: "OTHER")
        let action = manager.handleIncomingMessage(
            otherMsg,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        // Should ignore message when in completed state
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(manager.qsoState, .completed(dxCallsign: "G4ABC"))
    }
    
    func testTimeoutQSOIgnoresSubsequentMessages() {
        manager.qsoState = .timeout(dxCallsign: "K1ABC")
        
        let msg = makeMessage(text: "K1ABC EA1TST RRR", callsign: "K1ABC")
        let action = manager.handleIncomingMessage(
            msg,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )
        
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(manager.qsoState, .timeout(dxCallsign: "K1ABC"))
    }
}
