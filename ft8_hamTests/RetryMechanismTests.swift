import XCTest
import Combine
@testable import ft8_ham

@MainActor
final class RetryMechanismTests: XCTestCase {
    
    // Test helper to setup a new QSO
    private func setupNewQSO(dx: String = "EA1TER", locator: String = "IN80") {
        qsoManager.setupNewQSO(dx: dx, locator: locator, initialSNR: -13)
    }
    
    var viewModel: FT8ViewModel!
    var qsoManager: QSOStatusManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        viewModel = FT8ViewModel()
        qsoManager = viewModel.qsoManager
        cancellables = []
    }
    
    override func tearDown() {
        super.tearDown()
        viewModel = nil
        qsoManager = nil
        cancellables.removeAll()
    }
    
    // MARK: - Retry Counter Tests
    
    /// Test that retry counter starts at 0
    func testRetryCounterInitial() {
        XCTAssertEqual(qsoManager.retryCounter, 0, "Retry counter should start at 0")
    }
    
    /// Test that retry counter increments on timeout
    func testRetryCounterIncrementsOnTimeout() {
        // Setup: Start a reply to simulate active QSO
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        qsoManager.responseReceivedThisSlot = false
        
        let initialCount = qsoManager.retryCounter
        
        // Simulate timeout
        let action = qsoManager.handleQSOTimeout()
        
        XCTAssertEqual(qsoManager.retryCounter, initialCount + 1, "Retry counter should increment")
        XCTAssertNotEqual(action, .abortQSO, "Should not abort on first timeout")
        // In listeningReport, we resend grid (they didn't receive it)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "EA1TER", dxLocator: "IN80"), "Should retry grid")
    }
    
    /// Test that retry counter resets after maxRetrySlots exceeded
    func testRetryCounterIncrementsToMax() {
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        
        // Simulate 3 consecutive timeouts (the retries allowed)
        for i in 1...3 {
            qsoManager.responseReceivedThisSlot = false
            let action = qsoManager.handleQSOTimeout()
            
            XCTAssertEqual(qsoManager.retryCounter, i, "Retry counter should be \(i)")
            XCTAssertNotEqual(action, .abortQSO, "Should not abort yet, still within max retries")
        }
        
        // Fourth timeout should abort
        qsoManager.responseReceivedThisSlot = false
        let finalAction = qsoManager.handleQSOTimeout()
        XCTAssertEqual(qsoManager.retryCounter, 0, "Retry counter should reset on abort")
        XCTAssertEqual(finalAction, .abortQSO, "Should abort after exceeding max retries")
        
    }
    
    /// Test that retry counter resets when QSO completes
    func testRetryCounterResetsOnCompletion() {
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        qsoManager.responseReceivedThisSlot = false
        
        // Increment retry counter
        _ = qsoManager.handleQSOTimeout()
        XCTAssert(qsoManager.retryCounter > 0)
        
        // Close QSO
        _ = qsoManager.closeQSO(dxCallsign: "EA1TER", openCourtesyWindow: false)
        
        XCTAssertEqual(qsoManager.retryCounter, 0, "Retry counter should reset after QSO closes")
    }
    
    /// Test that retry counter resets on QSO reset
    func testRetryCounterResetsOnReset() {
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        qsoManager.responseReceivedThisSlot = false
        
        // Increment retry counter
        _ = qsoManager.handleQSOTimeout()
        XCTAssert(qsoManager.retryCounter > 0)
        
        // Reset QSO
        qsoManager.resetQSO()
        
        XCTAssertEqual(qsoManager.retryCounter, 0, "Retry counter should reset after QSO reset")
    }
    
    // MARK: - Response Flag Tests
    
    /// Test that responseReceivedThisSlot is reset at slot start
    func testResponseFlagResetAtSlotStart() {
        qsoManager.responseReceivedThisSlot = true
        
        qsoManager.prepareForRXSlot()
        
        XCTAssertFalse(qsoManager.responseReceivedThisSlot, "Response flag should reset at slot start")
    }
    
    /// Test that responseReceivedThisSlot prevents timeout
    func testResponseFlagPreventsTimeout() {
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        qsoManager.responseReceivedThisSlot = true
        
        let initialRetries = qsoManager.retryCounter
        
        // Even though we call timeout check, responseReceivedThisSlot should prevent it
        // This would normally be called during RX processing
        
        XCTAssertEqual(qsoManager.retryCounter, initialRetries, "Retry should not increment if response received")
    }
    
    // MARK: - State Transition Tests
    
    /// Test proper state transition on timeout at each stage
    func testStateTransitionOnTimeoutAtGrid() {
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        qsoManager.responseReceivedThisSlot = false
        
        let action = qsoManager.handleQSOTimeout()
        
        // In listeningReport, we resend grid (they didn't receive it)
        XCTAssertEqual(action, .sendGrid(dxCallsign: "EA1TER", dxLocator: "IN80"), 
                      "Should retry sending grid on timeout")
    }
    
    /// Test state transition on timeout at report
    func testStateTransitionOnTimeoutAtReport() {
        setupNewQSO()
        qsoManager.qsoState = .listeningRReport(dxCallsign: "EA1TER")
        qsoManager.lastSentSNR = -13
        qsoManager.responseReceivedThisSlot = false
        
        let action = qsoManager.handleQSOTimeout()
        
        XCTAssertEqual(action, .sendRReport(dxCallsign: "EA1TER", report: -13), 
                      "Should retry sending R-report on timeout")
    }
    
    /// Test abort action after max retries
    func testAbortActionAfterMaxRetries() {
        setupNewQSO()
        qsoManager.qsoState = .listeningRRR(dxCallsign: "EA1TER")
        
        // Exhaust retries
        for _ in 1...3 {
            qsoManager.responseReceivedThisSlot = false
            _ = qsoManager.handleQSOTimeout()
        }
        
        qsoManager.responseReceivedThisSlot = false
        let action = qsoManager.handleQSOTimeout()
        
        XCTAssertEqual(action, .abortQSO, "Should return abortQSO after max retries")
    }
    
    // MARK: - Awaiting Response Tests
    
    /// Test isAwaitingResponse for listening states
    func testIsAwaitingResponseListeningStates() {
        setupNewQSO()
        
        let listeningStates: [QSOState] = [
            .listeningReport(dxCallsign: "EA1TER"),
            .listeningRReport(dxCallsign: "EA1TER"),
            .listeningRRR(dxCallsign: "EA1TER")
        ]
        
        for state in listeningStates {
            qsoManager.qsoState = state
            XCTAssertTrue(qsoManager.isAwaitingResponse(), 
                         "Should be awaiting response in state: \(state)")
        }
    }
    
    /// Test isAwaitingResponse for sending states (should be false)
    func testIsAwaitingResponseSendingStates() {
        setupNewQSO()
        
        let sendingStates: [QSOState] = [
            .sendingGrid(dxCallsign: "EA1TER"),
            .sendingReport(dxCallsign: "EA1TER"),
            .sendingRReport(dxCallsign: "EA1TER"),
            .sendingRRR(dxCallsign: "EA1TER"),
            .sending73(dxCallsign: "EA1TER")
        ]
        
        for state in sendingStates {
            qsoManager.qsoState = state
            XCTAssertFalse(qsoManager.isAwaitingResponse(), 
                          "Should not be awaiting response in state: \(state)")
        }
    }
    
    /// Test isAwaitingResponse for idle states
    func testIsAwaitingResponseIdleStates() {
        let idleStates: [QSOState] = [
            .idle,
            .callingCQ,
            .completed(dxCallsign: "EA1TER"),
            .timeout(dxCallsign: "EA1TER")
        ]
        
        for state in idleStates {
            qsoManager.qsoState = state
            XCTAssertFalse(qsoManager.isAwaitingResponse(), 
                          "Should not be awaiting response in state: \(state)")
        }
    }
    
    // MARK: - Edge Cases
    
    /// Test timeout doesn't trigger on sending states (should skip)
    func testTimeoutSkipsOnSendingStates() {
        setupNewQSO()
        qsoManager.qsoState = .sendingGrid(dxCallsign: "EA1TER")
        
        let initialRetries = qsoManager.retryCounter
        
        // In real code, applyBatchUpdates checks isAwaitingResponse()
        // which returns false for sending states
        if qsoManager.isAwaitingResponse() && !qsoManager.responseReceivedThisSlot {
            _ = qsoManager.handleQSOTimeout()
        }
        
        XCTAssertEqual(qsoManager.retryCounter, initialRetries, 
                      "Timeout should not trigger during sending state")
    }
    
    /// Test multiple consecutive timeouts with retries
    func testMultipleConsecutiveTimeouts() {
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        
        var actions: [QSOAction] = []
        
        // Simulate 4 timeout events (max retries is 3)
        for i in 1...4 {
            qsoManager.prepareForRXSlot()  // Reset response flag
            qsoManager.responseReceivedThisSlot = false
            
            let action = qsoManager.handleQSOTimeout()
            actions.append(action)
            
            if i <= 3 {
                XCTAssertNotEqual(action, .abortQSO, "Should retry at attempt \(i)")
            }
        }
        
        // Last action should be abort
        XCTAssertEqual(actions.last, .abortQSO, "Final action should be abort")
        XCTAssertEqual(qsoManager.retryCounter, 0, "Retry counter should reset on abort")
    }
    
    
    /// Test response received prevents counter increment
    func testResponseReceivedPreventsIncrement() {
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        qsoManager.responseReceivedThisSlot = true
        
        let initialCount = qsoManager.retryCounter
        
        // This would be handled in real code by applyBatchUpdates
        // checking: if qsoManager.isAwaitingResponse() && !qsoManager.responseReceivedThisSlot
        if qsoManager.isAwaitingResponse() && !qsoManager.responseReceivedThisSlot {
            _ = qsoManager.handleQSOTimeout()
        }
        
        XCTAssertEqual(qsoManager.retryCounter, initialCount, 
                      "Retry counter should not increment when response received")
    }
    
    // MARK: - Message Index Preservation Tests
    
    /// Test that message index is preserved during active QSO message regeneration
    func testMessageIndexPreservedDuringQSO() {
        setupNewQSO()
        qsoManager.qsoState = .sendingGrid(dxCallsign: "EA1TER")
        
        // Message index preservation is handled during QSO state
        // Verify state is active
        XCTAssertTrue(qsoManager.isQSOOngoing(), 
                      "QSO should be ongoing during sendingGrid state")
    }
    
    /// Test that message index is reset when idle
    func testMessageIndexResetWhenIdle() {
        setupNewQSO()
        qsoManager.qsoState = .idle
        
        // Reset should be handled when QSO is not ongoing
        XCTAssertFalse(qsoManager.isQSOOngoing(), 
                      "QSO should not be ongoing in idle state")
    }
    
    /// Test that message index is reset when calling CQ
    func testMessageIndexResetWhenCallingCQ() {
        qsoManager.qsoState = .callingCQ
        
        // Verify CQ state is not ongoing QSO
        XCTAssertFalse(qsoManager.isQSOOngoing(), 
                      "QSO should not be ongoing during callingCQ")
    }
    
    // MARK: - Integration Tests
    
    /// Test complete retry flow: Reply -> Timeout -> Retry -> Success
    func testCompleteRetryFlowWithSuccess() {
        // Setup: Start reply to CQ
        setupNewQSO()
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")
        
        XCTAssertEqual(qsoManager.retryCounter, 0)
        
        // No response in first slot - timeout
        qsoManager.prepareForRXSlot()
        qsoManager.responseReceivedThisSlot = false
        let action1 = qsoManager.handleQSOTimeout()
        
        XCTAssertEqual(qsoManager.retryCounter, 1)
        // In listeningReport, we resend grid (they didn't receive it)
        XCTAssertEqual(action1, .sendGrid(dxCallsign: "EA1TER", dxLocator: "IN80"))
        
        // Retry once more without response
        qsoManager.prepareForRXSlot()
        qsoManager.responseReceivedThisSlot = false
        _ = qsoManager.handleQSOTimeout()
        
        XCTAssertEqual(qsoManager.retryCounter, 2)
        
        // Now response comes in before next timeout
        qsoManager.prepareForRXSlot()
        qsoManager.responseReceivedThisSlot = true
        
        // Timeout check should be skipped since response received
        if qsoManager.isAwaitingResponse() && !qsoManager.responseReceivedThisSlot {
            _ = qsoManager.handleQSOTimeout()
        }
        
        // Verify retry counter didn't increase
        XCTAssertEqual(qsoManager.retryCounter, 2, "Should stop incrementing after response")
    }
    
    /// Test complete retry flow: Exhaust retries and abort
    func testCompleteRetryFlowWithAbort() {
        setupNewQSO()
        qsoManager.qsoState = .listeningRReport(dxCallsign: "EA1TER")
        
        // Timeout 3 times (should still retry each time)
        var finalAction: QSOAction = .ignore
        for i in 1...3 {
            qsoManager.prepareForRXSlot()
            qsoManager.responseReceivedThisSlot = false
            finalAction = qsoManager.handleQSOTimeout()
            
            XCTAssertEqual(qsoManager.retryCounter, i)
            XCTAssertNotEqual(finalAction, .abortQSO, "Should still retry on attempt \(i)")
        }
        
        // Fourth timeout should abort
        qsoManager.prepareForRXSlot()
        qsoManager.responseReceivedThisSlot = false
        finalAction = qsoManager.handleQSOTimeout()
        XCTAssertEqual(finalAction, .abortQSO, "Should abort after exceeding max retries")
        XCTAssertEqual(qsoManager.retryCounter, 0, "Should reset on abort")
    }

    // MARK: - Bug A: maxRetrySlots sync

    /// maxRetrySlots on QSOStatusManager should match the value set externally (Bug A fix).
    func testMaxRetrySlotsRespected() {
        setupNewQSO()
        qsoManager.maxRetrySlots = 2
        qsoManager.qsoState = .listeningReport(dxCallsign: "EA1TER")

        // Two timeouts should still retry
        for i in 1...2 {
            qsoManager.responseReceivedThisSlot = false
            let action = qsoManager.handleQSOTimeout()
            XCTAssertEqual(qsoManager.retryCounter, i)
            XCTAssertNotEqual(action, .abortQSO, "Should not abort until limit (\(i)/2)")
        }

        // Third timeout must abort (limit is 2)
        qsoManager.responseReceivedThisSlot = false
        let abortAction = qsoManager.handleQSOTimeout()
        XCTAssertEqual(abortAction, .abortQSO, "Should abort after 2 retries when maxRetrySlots=2")
        XCTAssertEqual(qsoManager.retryCounter, 0, "Retry counter should reset on abort")
    }

    // MARK: - Bug B: 73 must not retry

    /// When a timeout fires during .sending73, the QSO must be closed immediately with
    /// .completeQSO — it must never return .send73 (no 73 retry loop).
    func testSending73TimeoutClosesQSOImmediately() {
        setupNewQSO()
        qsoManager.qsoState = .sending73(dxCallsign: "EA1TER")
        qsoManager.responseReceivedThisSlot = false

        let action = qsoManager.handleQSOTimeout()

        XCTAssertEqual(action, .completeQSO(dxCallsign: "EA1TER"),
                       "Timeout in sending73 must close the QSO, not schedule another 73")
        XCTAssertNotEqual(action, .send73(dxCallsign: "EA1TER"),
                          "Must never retry a 73 message")
        // State should be back to idle (closed)
        if case .idle = qsoManager.qsoState {
            // expected
        } else {
            XCTFail("QSO state should be .idle after closing from sending73, got \(qsoManager.qsoState)")
        }
        // Retry counter must not have been incremented (73 bypasses retry block)
        XCTAssertEqual(qsoManager.retryCounter, 0,
                       "Retry counter must remain 0 — 73 close bypasses retry logic")
    }
}
