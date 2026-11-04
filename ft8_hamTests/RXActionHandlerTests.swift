import XCTest
@testable import ft8_ham

@MainActor
final class RXActionHandlerTests: XCTestCase {
    
    var viewModel: FT8ViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = FT8ViewModel()
        viewModel.callsign = "EA4IQL"
        viewModel.locator = "IN80"
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - send73 Tests
    
    func testSend73SetsCorrectDXCallsign() {
        let action = QSOAction.send73(dxCallsign: "EA1TER")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "EA1TER", "dxCallsign should be set to EA1TER")
    }
    
    func testSend73SelectsCorrectMessageIndex() {
        let action = QSOAction.send73(dxCallsign: "EA1TER")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.selectedMessageIndex, 5, "selectedMessageIndex should be 5 for 73 message")
    }
    
    func testSend73RegeneratesMessages() {
        viewModel.dxCallsign = "EA1TER"
        viewModel.dxLocator = "IN70"
        _ = viewModel.allMessages
        
        let action = QSOAction.send73(dxCallsign: "EA2ABC")
        viewModel.handleRXAction(action)
        
        // Messages should be regenerated after dxCallsign changes
        XCTAssertEqual(viewModel.dxCallsign, "EA2ABC", "dxCallsign should be updated to EA2ABC")
        XCTAssertEqual(viewModel.allMessages[5], "EA2ABC EA4IQL 73", "Message [5] should contain new DX callsign")
    }
    
    func testSend73WithEmptyDXGeneratesCorrectMessage() {
        let action = QSOAction.send73(dxCallsign: "")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "", "dxCallsign should be empty")
        // Message composer uses XXXXXX for empty DX
        XCTAssertEqual(viewModel.allMessages[5], "XXXXXX EA4IQL 73", "Message [5] should use placeholder for empty DX")
    }
    
    // MARK: - sendRR73 Tests
    
    func testSendRR73SetsCorrectDXCallsign() {
        let action = QSOAction.sendRR73(dxCallsign: "EA1TER")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "EA1TER", "dxCallsign should be set to EA1TER")
    }
    
    func testSendRR73SelectsCorrectMessageIndex() {
        let action = QSOAction.sendRR73(dxCallsign: "EA1TER")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.selectedMessageIndex, 6, "selectedMessageIndex should be 6 for RR73 message")
    }
    
    func testSendRR73RegeneratesMessages() {
        viewModel.dxCallsign = "EA1TER"
        viewModel.dxLocator = "IN70"
        
        let action = QSOAction.sendRR73(dxCallsign: "EA2ABC")
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "EA2ABC", "dxCallsign should be updated to EA2ABC")
        XCTAssertEqual(viewModel.allMessages[6], "EA2ABC EA4IQL RR73", "Message [6] should contain new DX callsign")
    }
    
    func testSendRR73WithEmptyDXGeneratesCorrectMessage() {
        let action = QSOAction.sendRR73(dxCallsign: "")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "", "dxCallsign should be empty")
        XCTAssertEqual(viewModel.allMessages[6], "XXXXXX EA4IQL RR73", "Message [6] should use placeholder for empty DX")
    }
    
    // MARK: - Courtesy 73 Scenario (Integration)
    
    func testCourtesy73AfterQSOCompletion() {
        // Simulate QSO completion with EA1TER
        viewModel.dxCallsign = "EA1TER"
        viewModel.dxLocator = "IN70"
        viewModel.qsoManager.lockedDXCallsign = "EA1TER"
        viewModel.qsoManager.lastCourtesyDXCallsign = "EA1TER"
        
        // Courtesy 73 from the same DX
        let action = QSOAction.send73(dxCallsign: "EA1TER")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "EA1TER", "DX should remain EA1TER")
        XCTAssertEqual(viewModel.selectedMessageIndex, 5, "Should select 73 message")
        XCTAssertEqual(viewModel.allMessages[5], "EA1TER EA4IQL 73", "Message should use courtesy DX")
    }
    
    func testDXCallsignChangeTriggersMessageRefresh() {
        viewModel.dxCallsign = "EA2ABC"
        viewModel.dxLocator = "FN32"
        viewModel.allMessages = viewModel.generateMessages()
        
        let msg2Index = viewModel.allMessages[2] // Should be "EA2ABC EA4IQL -15"
        XCTAssertTrue(msg2Index.contains("EA2ABC"), "Initial message should reference EA2ABC")
        
        // Change DX via send73
        let action = QSOAction.send73(dxCallsign: "EA3XYZ")
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "EA3XYZ", "DX should be updated")
        XCTAssertTrue(viewModel.allMessages[5].contains("EA3XYZ"), "Updated message should reference EA3XYZ")
        XCTAssertFalse(viewModel.allMessages[5].contains("EA2ABC"), "Updated message should not reference old DX")
    }
    
    // MARK: - Edge Cases
    
    func testSend73WithLongCallsign() {
        let longCall = "W5ABC/M"
        let action = QSOAction.send73(dxCallsign: longCall)
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, longCall, "Should accept long callsign with suffix")
        // FT8 message has 18-char limit, so it will be truncated
        XCTAssertTrue(viewModel.allMessages[5].count <= 18, "Message should respect FT8 18-char limit")
    }
    
    func testSend73WithLowercaseCallsign() {
        let action = QSOAction.send73(dxCallsign: "ea1ter")
        
        viewModel.handleRXAction(action)
        
        XCTAssertEqual(viewModel.dxCallsign, "ea1ter", "Should preserve case as-is")
        // Message composer should uppercase it
        XCTAssertTrue(viewModel.allMessages[5].contains("EA1TER"), "Message should uppercase the callsign")
    }
    
    func testMultipleSend73CallsUpdateCorrectly() {
        let action1 = QSOAction.send73(dxCallsign: "EA1TER")
        viewModel.handleRXAction(action1)
        XCTAssertEqual(viewModel.dxCallsign, "EA1TER")
        
        let action2 = QSOAction.send73(dxCallsign: "EA2ABC")
        viewModel.handleRXAction(action2)
        XCTAssertEqual(viewModel.dxCallsign, "EA2ABC")
        
        let action3 = QSOAction.send73(dxCallsign: "EA3XYZ")
        viewModel.handleRXAction(action3)
        XCTAssertEqual(viewModel.dxCallsign, "EA3XYZ")
        
        XCTAssertEqual(viewModel.allMessages[5], "EA3XYZ EA4IQL 73", "Final message should use last DX")
    }
    
    // MARK: - Full Courtesy 73 Integration Test
    
    func testCourtesyListeningFullFlow() {
        // 1. Start a QSO with EA1TER
        viewModel.dxCallsign = "EA1TER"
        viewModel.dxLocator = "IN70"
        viewModel.qsoManager.setupNewQSO(dx: "EA1TER", locator: "IN70", initialSNR: -10)
        viewModel.qsoManager.qsoState = .sending73(dxCallsign: "EA1TER")
        
        // 2. Complete the QSO (this opens courtesy window)
        let closeAction = viewModel.qsoManager.closeQSO(dxCallsign: "EA1TER", openCourtesyWindow: true)
        XCTAssertEqual(closeAction, .completeQSO(dxCallsign: "EA1TER"))
        
        // 3. Apply completeQSO action - this resets radio state
        viewModel.handleRXAction(closeAction)
        
        // 4. Verify courtesy window is open
        XCTAssertEqual(viewModel.qsoManager.lastCourtesyDXCallsign, "EA1TER", "Courtesy DX should be preserved")
        XCTAssertNotNil(viewModel.qsoManager.courtesyDeadline, "Courtesy deadline should be set")
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle, "State should be idle")
        
        // 5. Simulate receiving courtesy 73 from EA1TER
        let courtesy73 = FT8Message(
            text: "EA4IQL EA1TER 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = viewModel.qsoManager.handleIncomingMessage(
            courtesy73,
            myCallsign: "EA4IQL",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        // 6. Should return send73 action with the courtesy DX callsign
        XCTAssertEqual(action, .send73(dxCallsign: "EA1TER"), "Should trigger courtesy 73 reply")
        
        // 7. Apply the action - THIS is where the fix matters
        viewModel.handleRXAction(action)
        
        // 8. Verify dxCallsign is set correctly from the action
        XCTAssertEqual(viewModel.dxCallsign, "EA1TER", "dxCallsign should be set from action, not empty")
        XCTAssertEqual(viewModel.selectedMessageIndex, 5, "Should select 73 message")
        
        // 9. Verify the generated message uses EA1TER, not XXXXXX
        XCTAssertTrue(viewModel.allMessages[5].contains("EA1TER"), "Message should contain EA1TER")
        XCTAssertFalse(viewModel.allMessages[5].contains("XXXXXX"), "Message should NOT contain XXXXXX placeholder")
    }
    
    func testCourtesyWindowExpiresAfterDeadline() {
        // Setup and complete QSO
        viewModel.dxCallsign = "EA1TER"
        viewModel.qsoManager.setupNewQSO(dx: "EA1TER", locator: "IN70", initialSNR: -10)
        viewModel.qsoManager.qsoState = .sending73(dxCallsign: "EA1TER")
        
        let closeAction = viewModel.qsoManager.closeQSO(dxCallsign: "EA1TER", openCourtesyWindow: true)
        viewModel.handleRXAction(closeAction)
        
        // Expire the courtesy window by setting deadline in the past
        viewModel.qsoManager.courtesyDeadline = Date().addingTimeInterval(-1)
        
        // Try courtesy 73 after deadline
        let courtesy73 = FT8Message(
            text: "EA4IQL EA1TER 73",
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action = viewModel.qsoManager.handleIncomingMessage(
            courtesy73,
            myCallsign: "EA4IQL",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        
        // Should ignore since deadline passed
        XCTAssertEqual(action, .ignore, "Should ignore courtesy 73 after deadline expires")
    }
    
    func testCourtesy73OnlySentOnce() {
        // Setup and complete QSO
        viewModel.dxCallsign = "EA1TER"
        viewModel.qsoManager.setupNewQSO(dx: "EA1TER", locator: "IN70", initialSNR: -10)
        viewModel.qsoManager.qsoState = .sending73(dxCallsign: "EA1TER")
        
        let closeAction = viewModel.qsoManager.closeQSO(dxCallsign: "EA1TER", openCourtesyWindow: true)
        viewModel.handleRXAction(closeAction)
        
        // First courtesy 73
        let courtesy73_1 = FT8Message(
            text: "EA4IQL EA1TER 73",
            mode: .ft8,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action1 = viewModel.qsoManager.handleIncomingMessage(
            courtesy73_1,
            myCallsign: "EA4IQL",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action1, .send73(dxCallsign: "EA1TER"), "First courtesy should trigger reply")
        viewModel.handleRXAction(action1)
        
        // Second courtesy 73 from same DX
        let courtesy73_2 = FT8Message(
            text: "EA4IQL EA1TER 73",
            mode: .ft8,
            timestamp: Date(),
            measuredSNR: -5,
            frequency: 14074000,
            band: .band20m
        )
        
        let action2 = viewModel.qsoManager.handleIncomingMessage(
            courtesy73_2,
            myCallsign: "EA4IQL",
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )
        XCTAssertEqual(action2, .ignore, "Second courtesy 73 should be ignored")
    }
}
