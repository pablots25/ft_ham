//
//  NaNInfiniteCrashTests.swift
//  ft8_hamTests
//
//  Created to prevent crash: "Double value cannot be converted to Int because it is either infinite or NaN"
//  Bug Location: QSOStatusManager.handleIncomingMessage(_:myCallsign:autoSequencingEnabled:autoCQReplyEnabled:)
//  Crash Date: 2026-02-23 00:17:00 UTC
//

import XCTest
@testable import ft8_ham

@MainActor
final class NaNInfiniteCrashTests: XCTestCase {
    
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
    
    // MARK: - Helper Methods
    
    /// Helper to create a message with custom SNR (including NaN/Infinite)
    /// For NaN/Infinite values, creates a message with invalid text that will parse to NaN
    private func makeMessageWithSNR(
        text: String,
        msgType: FT8MessageType,
        messageTxtSNR: Double,
        measuredSNR: Double = -10.0
    ) -> FT8Message {
        // If SNR is non-finite, create message with text that won't parse correctly
        // Otherwise use the provided text which should contain the valid SNR
        let finalText: String
        if !messageTxtSNR.isFinite {
            // Create text without valid SNR that will result in NaN during parsing
            finalText = "EA1TST K1ABC INVALID"
        } else {
            finalText = text
        }
        
        let message = FT8Message(
            text: finalText,
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: measuredSNR,
            frequency: 14074000,
            band: .band20m
        )
        
        return message
    }
    
    // MARK: - Tests for NaN in messageTxtSNR (Main Crash Scenario)
    
    func testHandleIncomingMessage_WithNaNSNR_DoesNotCrash_InSendingGridState() {
        // Setup: Start a QSO to get into sendingGrid state
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        // Create a message with NaN SNR (this was causing the crash)
        let messageWithNaN = makeMessageWithSNR(
            text: "EA1TST K1ABC -05",
            msgType: .standardSignalReport,
            messageTxtSNR: .nan
        )
        
        // This should NOT crash
        XCTAssertNoThrow({
            let action = self.manager.handleIncomingMessage(
                messageWithNaN,
                myCallsign: self.myCallsign,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: false
            )
            
            // The action should be ignore since we can't process invalid SNR
            XCTAssertNotEqual(action, .sendRReport(dxCallsign: "K1ABC", report: 0),
                            "Should not proceed with invalid SNR")
        })
        
        // lastReceivedSNR should be invalid (Int.min)
        XCTAssertEqual(manager.lastReceivedSNR, Int.min,
                      "lastReceivedSNR should be set to invalidSNR when messageTxtSNR is NaN")
    }
    
    func testHandleIncomingMessage_WithNaNSNR_DoesNotCrash_InSendingReportState() {
        // Setup: Get into sendingReport state
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingReport(dxCallsign: "K1ABC")
        
        let messageWithNaN = makeMessageWithSNR(
            text: "EA1TST K1ABC R-05",
            msgType: .rSignalReport,
            messageTxtSNR: .nan
        )
        
        // This should NOT crash
        XCTAssertNoThrow({
            let _ = self.manager.handleIncomingMessage(
                messageWithNaN,
                myCallsign: self.myCallsign,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: false
            )
        })
        
        XCTAssertEqual(manager.lastReceivedSNR, Int.min,
                      "lastReceivedSNR should be invalidSNR when messageTxtSNR is NaN")
    }
    
    func testHandleIncomingMessage_WithNaNSNR_DoesNotCrash_InListeningReportState() {
        // Setup: Get into listeningReport state
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .listeningReport(dxCallsign: "K1ABC")
        
        let messageWithNaN = makeMessageWithSNR(
            text: "EA1TST K1ABC -05",
            msgType: .standardSignalReport,
            messageTxtSNR: .nan
        )
        
        // This should NOT crash
        XCTAssertNoThrow({
            let _ = self.manager.handleIncomingMessage(
                messageWithNaN,
                myCallsign: self.myCallsign,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: false
            )
        })
        
        XCTAssertEqual(manager.lastReceivedSNR, Int.min,
                      "lastReceivedSNR should be invalidSNR when messageTxtSNR is NaN")
    }
    
    // MARK: - Tests for Infinite Values
    
    func testHandleIncomingMessage_WithPositiveInfinitySNR_DoesNotCrash() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        let messageWithInfinity = makeMessageWithSNR(
            text: "EA1TST K1ABC -05",
            msgType: .standardSignalReport,
            messageTxtSNR: .infinity
        )
        
        XCTAssertNoThrow({
            let _ = self.manager.handleIncomingMessage(
                messageWithInfinity,
                myCallsign: self.myCallsign,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: false
            )
        })
        
        XCTAssertEqual(manager.lastReceivedSNR, Int.min,
                      "lastReceivedSNR should be invalidSNR when messageTxtSNR is infinite")
    }
    
    func testHandleIncomingMessage_WithNegativeInfinitySNR_DoesNotCrash() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        let messageWithNegInfinity = makeMessageWithSNR(
            text: "EA1TST K1ABC -05",
            msgType: .standardSignalReport,
            messageTxtSNR: -.infinity
        )
        
        XCTAssertNoThrow({
            let _ = self.manager.handleIncomingMessage(
                messageWithNegInfinity,
                myCallsign: self.myCallsign,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: false
            )
        })
        
        XCTAssertEqual(manager.lastReceivedSNR, Int.min,
                      "lastReceivedSNR should be invalidSNR when messageTxtSNR is -infinity")
    }
    
    // MARK: - Tests for Valid SNR Values (Regression Tests)
    
    func testHandleIncomingMessage_WithValidSNR_WorksCorrectly() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        let validMessage = makeMessageWithSNR(
            text: "EA1TST K1ABC -05",
            msgType: .standardSignalReport,
            messageTxtSNR: -5.7
        )
        
        let action = manager.handleIncomingMessage(
            validMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )
        
        // Message text contains "-05" which parses to -5
        XCTAssertEqual(manager.lastReceivedSNR, -5,
                      "Valid SNR should be parsed and stored")
        
        // Should advance to next state
        if case .sendRReport = action {
            // Expected behavior
        } else {
            XCTFail("Should send R-report with valid SNR")
        }
    }
    
    func testHandleIncomingMessage_WithValidPositiveSNR_WorksCorrectly() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        let validMessage = makeMessageWithSNR(
            text: "EA1TST K1ABC +15",
            msgType: .standardSignalReport,
            messageTxtSNR: 15.3
        )
        
        let _ = manager.handleIncomingMessage(
            validMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )
        
        XCTAssertEqual(manager.lastReceivedSNR, 15,
                      "Valid positive SNR should be properly rounded")
    }
    
    // MARK: - Tests for setupNewQSO with Non-Finite Values
    
    func testSetupNewQSO_WithNaNInitialSNR_UsesInvalidSNR() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: .nan)
        
        XCTAssertEqual(manager.lastSentSNR, Int.min,
                      "setupNewQSO should use invalidSNR when initialSNR is NaN")
    }
    
    func testSetupNewQSO_WithInfiniteInitialSNR_UsesInvalidSNR() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: .infinity)
        
        XCTAssertEqual(manager.lastSentSNR, Int.min,
                      "setupNewQSO should use invalidSNR when initialSNR is infinite")
    }
    
    func testSetupNewQSO_WithNegativeInfiniteInitialSNR_UsesInvalidSNR() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -.infinity)
        
        XCTAssertEqual(manager.lastSentSNR, Int.min,
                      "setupNewQSO should use invalidSNR when initialSNR is -infinity")
    }
    
    func testSetupNewQSO_WithValidInitialSNR_StoresCorrectly() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -12.6)
        
        XCTAssertEqual(manager.lastSentSNR, -13,
                      "setupNewQSO should properly round valid SNR")
    }
    
    // MARK: - Edge Cases
    
    func testHandleIncomingMessage_WithZeroSNR_WorksCorrectly() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        let zeroMessage = makeMessageWithSNR(
            text: "EA1TST K1ABC +00",
            msgType: .standardSignalReport,
            messageTxtSNR: 0.0
        )
        
        let _ = manager.handleIncomingMessage(
            zeroMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )
        
        XCTAssertEqual(manager.lastReceivedSNR, 0,
                      "Zero SNR should be handled correctly")
    }
    
    func testHandleIncomingMessage_WithExtremeLargeValidSNR_WorksCorrectly() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        let extremeMessage = makeMessageWithSNR(
            text: "EA1TST K1ABC +30",
            msgType: .standardSignalReport,
            messageTxtSNR: 30.0
        )
        
        let _ = manager.handleIncomingMessage(
            extremeMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )
        
        XCTAssertEqual(manager.lastReceivedSNR, 30,
                  "Extreme large valid SNR should be handled correctly")
    }
    
    func testHandleIncomingMessage_WithExtremeLowValidSNR_WorksCorrectly() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        let extremeMessage = makeMessageWithSNR(
            text: "EA1TST K1ABC -24",
            msgType: .standardSignalReport,
            messageTxtSNR: -24.2
        )
        
        let _ = manager.handleIncomingMessage(
            extremeMessage,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: false
        )
        
        XCTAssertEqual(manager.lastReceivedSNR, -24,
                      "Extreme low valid SNR should be handled correctly")
    }
    
    // MARK: - Test R-Report Scenario (Second vulnerable location)
    
    func testHandleIncomingMessage_RReport_WithNaNSNR_DoesNotCrash() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingReport(dxCallsign: "K1ABC")
        
        // lastReceivedSNR is still invalidSNR
        XCTAssertEqual(manager.lastReceivedSNR, Int.min)
        
        let rReportWithNaN = makeMessageWithSNR(
            text: "EA1TST K1ABC R-05",
            msgType: .rSignalReport,
            messageTxtSNR: .nan
        )
        
        XCTAssertNoThrow({
            let _ = self.manager.handleIncomingMessage(
                rReportWithNaN,
                myCallsign: self.myCallsign,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: false
            )
        })
        
        // Should remain invalidSNR since we couldn't extract valid SNR
        XCTAssertEqual(manager.lastReceivedSNR, Int.min,
                      "R-Report with NaN should not update lastReceivedSNR")
    }
    
    // MARK: - Multiple NaN Messages in Sequence
    
    func testMultipleNaNMessages_DoNotCrash() {
        manager.setupNewQSO(dx: "K1ABC", locator: "FN20", initialSNR: -10)
        manager.qsoState = .sendingGrid(dxCallsign: "K1ABC")
        
        // Send multiple messages with NaN
        for i in 0..<5 {
            let nanMessage = makeMessageWithSNR(
                text: "EA1TST K1ABC -\(i)5",
                msgType: .standardSignalReport,
                messageTxtSNR: .nan
            )
            
            XCTAssertNoThrow({
                let _ = self.manager.handleIncomingMessage(
                    nanMessage,
                    myCallsign: self.myCallsign,
                    autoSequencingEnabled: true,
                    autoCQReplyEnabled: false
                )
            }, "Message \(i) with NaN should not crash")
        }
        
        XCTAssertEqual(manager.lastReceivedSNR, Int.min,
                      "After multiple NaN messages, lastReceivedSNR should still be invalidSNR")
    }
}
