import XCTest
@testable import ft8_ham

@MainActor
final class QSOBugFixTests: XCTestCase {
    
    var manager: QSOStatusManager!
    let myCallsign = "EA1ABC"
    
    override func setUp() {
        super.setUp()
        manager = QSOStatusManager()
    }
    
    // MARK: - Bug Fix #1: Completed QSO should not be re-triggered during courtesy window
    
    func testCompletedQSOBlocksRestartDuringCourtesyWindow() {
        // Setup: Start a QSO with EA2ABC
        manager.setupNewQSO(dx: "EA2ABC", locator: "FN31", initialSNR: -10)
        manager.qsoState = .sending73(dxCallsign: "EA2ABC")
        manager.lockedDXCallsign = "EA2ABC"
        
        // Complete the QSO (resets operational state to idle, but tracks qsoAlreadyLogged)
        let completeAction = manager.closeQSO(dxCallsign: "EA2ABC", openCourtesyWindow: true)
        
        XCTAssertEqual(completeAction, .completeQSO(dxCallsign: "EA2ABC"))
        XCTAssertEqual(manager.qsoState, .idle, "Operational state should reset to idle for new QSOs")
        XCTAssertTrue(manager.qsoAlreadyLogged, "Should track that this QSO was already logged")
        XCTAssertEqual(manager.lockedDXCallsign, "", "Lock should be cleared")
        XCTAssertNotNil(manager.lastCourtesyDXCallsign, "Should track courtesy DX")
        
        // Receive another message from EA2ABC during courtesy window
        let anotherMsg = FT8Message(
            text: "EA1ABC EA2ABC -05",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = manager.handleIncomingMessage(
            anotherMsg,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        // Should be ignored (qsoAlreadyLogged prevents restarting), not trigger a new QSO
        XCTAssertEqual(action, .ignore, "Should ignore - already logged for this contact")
        XCTAssertEqual(manager.qsoState, .idle, "Should remain idle")
    }
    
    func testCompletedQSOAllowsNewQSOWithDifferentDX() {
        // Complete QSO with EA2ABC
        manager.setupNewQSO(dx: "EA2ABC", locator: "FN31", initialSNR: -10)
        manager.qsoState = .sending73(dxCallsign: "EA2ABC")
        manager.lockedDXCallsign = "EA2ABC"
        
        let _ = manager.closeQSO(dxCallsign: "EA2ABC", openCourtesyWindow: true)
        
        XCTAssertEqual(manager.qsoState, .idle)
        XCTAssertTrue(manager.qsoAlreadyLogged, "Still marked as logged for EA2ABC")
        
        // Now receive CQ from different DX (EA3XYZ)
        let newCQ = FT8Message(
            text: "CQ EA3XYZ FN20",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -8,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = manager.handleIncomingMessage(
            newCQ,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        // Should start new QSO with EA3XYZ
        XCTAssertEqual(action, .sendGrid(dxCallsign: "EA3XYZ", dxLocator: "FN20"))
        XCTAssertEqual(manager.lockedDXCallsign, "EA3XYZ", "Should lock new DX")
        XCTAssertFalse(manager.qsoAlreadyLogged, "Should have reset qsoAlreadyLogged for new QSO")
    }
    
    // MARK: - Bug Fix #2: Lost QSO should timeout after max retries
    
    func testLostQSOTimeoutAfterMaxRetries() {
        // Start QSO
        manager.setupNewQSO(dx: "W5XYZ", locator: "EM12", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "W5XYZ")
        manager.lastSentSNR = 8
        manager.responseReceivedThisSlot = false
        
        XCTAssertEqual(manager.retryCounter, 0)
        
        // Simulate 3 timeouts (maxRetrySlots = 3)
        var action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 1)
        XCTAssertNotEqual(action, .abortQSO, "First timeout should retry")
        
        manager.responseReceivedThisSlot = false
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 2)
        XCTAssertNotEqual(action, .abortQSO, "Second timeout should retry")
        
        manager.responseReceivedThisSlot = false
        action = manager.handleQSOTimeout()
        XCTAssertEqual(manager.retryCounter, 3)
        XCTAssertNotEqual(action, .abortQSO, "Third timeout should retry")
        
        // Fourth timeout should abort (exceeds maxRetrySlots)
        manager.responseReceivedThisSlot = false
        action = manager.handleQSOTimeout()
        XCTAssertEqual(action, .abortQSO, "Fourth timeout should abort")
        XCTAssertEqual(manager.qsoState, .idle, "State resets to idle after abort")
        XCTAssertEqual(manager.lockedDXCallsign, "", "Lock should be cleared on abort")
        XCTAssertEqual(manager.retryCounter, 0, "Retry counter should be reset")
    }
    
    func testLostQSODoesNotHangInfinitely() {
        // Start QSO at listeningRReport stage (waiting for RRR)
        manager.setupNewQSO(dx: "K1ABC", locator: "FN31", initialSNR: -10)
        manager.qsoState = .listeningRReport(dxCallsign: "K1ABC")
        manager.lastSentSNR = 12
        
        var timeoutCount = 0
        let maxTimeouts = 10  // Prevent infinite loop in test
        
        while timeoutCount < maxTimeouts {
            manager.responseReceivedThisSlot = false
            let action = manager.handleQSOTimeout()
            timeoutCount += 1
            
            if action == .abortQSO {
                // Good! Should abort before hitting maxTimeouts
                XCTAssertLessThan(timeoutCount, maxTimeouts, "Should abort before \(maxTimeouts) attempts")
                XCTAssertEqual(manager.qsoState, .idle, "State should be idle after abort")
                return
            }
        }
        
        XCTFail("QSO did not abort after \(maxTimeouts) timeout attempts - infinite loop detected!")
    }
    
    func testRetryCounterResetsOnNewQSO() {
        // First QSO times out
        manager.setupNewQSO(dx: "EA1TST", locator: "IN80", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "EA1TST")
        manager.responseReceivedThisSlot = false
        
        let _ = manager.handleQSOTimeout()
        XCTAssertNotEqual(manager.retryCounter, 0, "Retry counter should increment after first timeout")
        
        // Now start new QSO with different DX
        manager.setupNewQSO(dx: "EA2ABC", locator: "FN31", initialSNR: -10)
        XCTAssertEqual(manager.retryCounter, 0, "Retry counter should reset on new QSO")
        XCTAssertEqual(manager.lockedDXCallsign, "EA2ABC")
        XCTAssertFalse(manager.qsoAlreadyLogged, "qsoAlreadyLogged should reset for new QSO")
    }
    
    func testCourtesyWindowDoesNotRestartQSO() {
        // Complete a QSO
        manager.setupNewQSO(dx: "EA5TST", locator: "IN80", initialSNR: -10)
        manager.qsoState = .sending73(dxCallsign: "EA5TST")
        let _ = manager.closeQSO(dxCallsign: "EA5TST", openCourtesyWindow: true)
        
        XCTAssertTrue(manager.courtesyListeningEnabled)
        XCTAssertNotNil(manager.lastCourtesyDXCallsign)
        
        // Receive courtesy 73 from same DX
        let courtesy73 = FT8Message(
            text: "EA1ABC EA5TST 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -12,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = manager.handleIncomingMessage(
            courtesy73,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        // Should reply once with courtesy 73, but NOT restart the QSO
        XCTAssertEqual(
            action,
            .send73(dxCallsign: "EA5TST"),
            "Should reply with courtesy 73"
        )
        XCTAssertEqual(manager.qsoState, .idle, "Should remain idle, not restart")
        XCTAssertTrue(manager.courtesy73SentAfterQSO, "Should mark courtesy sent")
    }
}
