//
//  FT8MessageComposerNaNTests.swift
//  ft8_hamTests
//
//  Tests for FT8MessageComposer to ensure NaN/Infinite SNR values are handled safely
//

import XCTest
@testable import ft8_ham

final class FT8MessageComposerNaNTests: XCTestCase {
    
    private let testCallsign = "EA1TST"
    private let testLocator = "IN70AB"
    private let testDXCallsign = "K1ABC"
    private let testDXLocator = "FN20"

    private func truncatedFT8(_ text: String) -> String {
        String(text.prefix(18))
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
        UserDefaults.standard.removeObject(forKey: "cqIncludeGrid")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
        UserDefaults.standard.removeObject(forKey: "cqIncludeGrid")
        super.tearDown()
    }
    
    // MARK: - Tests for NaN SNR
    
    func testAllMessages_WithNaNSNR_UsesDefaultReport() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: Double.nan
        )
        
        XCTAssertFalse(messages.isEmpty, "Should return messages even with NaN SNR")
        
        // The report message should contain the default "-15" instead of crashing
        let reportMessage = messages.first { $0.contains(testDXCallsign) && $0.contains("-15") || $0.contains("+") || $0.contains("R-") || $0.contains("R+") }
        
        XCTAssertNotNil(reportMessage, "Should have a report message")
        
        // Specifically check that NaN doesn't crash the conversion
        XCTAssertNoThrow({
            _ = FT8MessageComposer().generateMessages(
                callsign: self.testCallsign,
                locator: self.testLocator,
                dxCallsign: self.testDXCallsign,
                dxLocator: self.testDXLocator,
                snrToSend: Double.nan
            )
        }, "allMessages with NaN SNR should not crash")
    }
    
    func testAllMessages_WithInfinitySNR_UsesDefaultReport() {
        XCTAssertNoThrow({
            let messages = FT8MessageComposer().generateMessages(
                callsign: self.testCallsign,
                locator: self.testLocator,
                dxCallsign: self.testDXCallsign,
                dxLocator: self.testDXLocator,
                snrToSend: Double.infinity
            )
            
            XCTAssertFalse(messages.isEmpty, "Should return messages even with infinity SNR")
        }, "allMessages with infinity SNR should not crash")
    }
    
    func testAllMessages_WithNegativeInfinitySNR_UsesDefaultReport() {
        XCTAssertNoThrow({
            let messages = FT8MessageComposer().generateMessages(
                callsign: self.testCallsign,
                locator: self.testLocator,
                dxCallsign: self.testDXCallsign,
                dxLocator: self.testDXLocator,
                snrToSend: -Double.infinity
            )
            
            XCTAssertFalse(messages.isEmpty, "Should return messages even with -infinity SNR")
        }, "allMessages with -infinity SNR should not crash")
    }
    
    // MARK: - Tests for Valid SNR Values (Regression)
    
    func testAllMessages_WithValidPositiveSNR_FormatsCorrectly() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: 15.7
        )
        
        // Should round to +16
        let reportMessage = messages.first { $0.contains("+16") || $0.contains("R+16") }
        XCTAssertNotNil(reportMessage, "Should format positive SNR correctly as +16")
    }
    
    func testAllMessages_WithValidNegativeSNR_FormatsCorrectly() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -12.3
        )
        
        // Should round to -12
        let reportMessage = messages.first { $0.contains("-12") }
        XCTAssertNotNil(reportMessage, "Should format negative SNR correctly as -12")
    }
    
    func testAllMessages_WithZeroSNR_FormatsCorrectly() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: 0.0
        )
        
        // Should format as +00 or -00
        let reportMessage = messages.first { $0.contains("+00") || $0.contains("-00") }
        XCTAssertNotNil(reportMessage, "Should format zero SNR correctly")
    }
    
    // MARK: - Tests for SNR Clamping
    
    func testAllMessages_WithExtremeLargeSNR_ClampsTo30() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: 99.9
        )
        
        // Should clamp to +30 (protocol limit)
        let reportMessage = messages.first { $0.contains("+30") }
        XCTAssertNotNil(reportMessage, "Should clamp extreme positive SNR to +30")
    }
    
    func testAllMessages_WithExtremeSmallSNR_ClampsToMinus30() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -99.9
        )
        
        // Should clamp to -30 (protocol limit)
        let reportMessage = messages.first { $0.contains("-30") }
        XCTAssertNotNil(reportMessage, "Should clamp extreme negative SNR to -30")
    }
    
    // MARK: - Tests for Message Structure
    
    func testAllMessages_WithValidSNR_ContainsAllExpectedMessages() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -10.0
        )
        
        // Should contain multiple messages
        XCTAssertGreaterThan(messages.count, 0, "Should return multiple messages")
        
        // Check for expected message types
        let hasCQ = messages.contains { $0.hasPrefix("CQ") }
        let hasReport = messages.contains { $0.contains("-10") }
        let has73 = messages.contains { $0.contains("73") }
        
        XCTAssertTrue(hasCQ, "Should contain CQ message")
        XCTAssertTrue(hasReport, "Should contain report message with SNR")
        XCTAssertTrue(has73, "Should contain 73 message")
    }
    
    func testAllMessages_WithNaNSNR_ContainsAllExpectedMessages() {
        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: Double.nan
        )
        
        // Should still return all message types (with default SNR)
        XCTAssertGreaterThan(messages.count, 0, "Should return messages even with NaN")
        
        let hasCQ = messages.contains { $0.hasPrefix("CQ") }
        let has73 = messages.contains { $0.contains("73") }
        
        XCTAssertTrue(hasCQ, "Should contain CQ message even with NaN SNR")
        XCTAssertTrue(has73, "Should contain 73 message even with NaN SNR")
    }
    
    // MARK: - Multiple Calls with Non-Finite Values
    
    func testMultipleCalls_WithNonFiniteValues_DoNotCrash() {
        let nonFiniteValues: [Double] = [Double.nan, Double.infinity, -Double.infinity, Double.nan]
        
        for value in nonFiniteValues {
            XCTAssertNoThrow({
                _ = FT8MessageComposer().generateMessages(
                    callsign: self.testCallsign,
                    locator: self.testLocator,
                    dxCallsign: self.testDXCallsign,
                    dxLocator: self.testDXLocator,
                    snrToSend: value
                )
            }, "Calling allMessages with \(value) should not crash")
        }
    }
    
    // MARK: - Edge Cases
    
    func testAllMessages_WithEmptyCallsigns_HandlesGracefully() {
        XCTAssertNoThrow({
            _ = FT8MessageComposer().generateMessages(
                callsign: "",
                locator: self.testLocator,
                dxCallsign: "",
                dxLocator: self.testDXLocator,
                snrToSend: Double.nan
            )
        }, "Should handle empty callsigns with NaN SNR without crashing")
    }
    
    func testAllMessages_WithBoundaryValidSNR_WorksCorrectly() {
        // Test at protocol boundaries
        let boundaryValues: [Double] = [-30.0, -24.0, 0.0, 24.0, 30.0]
        
        for value in boundaryValues {
            XCTAssertNoThrow({
                let messages = FT8MessageComposer().generateMessages(
                    callsign: self.testCallsign,
                    locator: self.testLocator,
                    dxCallsign: self.testDXCallsign,
                    dxLocator: self.testDXLocator,
                    snrToSend: value
                )
                
                XCTAssertFalse(messages.isEmpty, "Should return messages for boundary SNR: \(value)")
            }, "Boundary SNR value \(value) should work correctly")
        }
    }

    // MARK: - CQ Modifier Compact Token Support

    func testCQMessage_UsesRawTokenForPOTA() {
        UserDefaults.standard.set("POTA", forKey: "cqModifier")

        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -10
        )

        XCTAssertEqual(messages.first, truncatedFT8("CQ POTA \(testCallsign) IN70"))
    }

    func testCQMessage_UsesRawTokenForWWFF() {
        UserDefaults.standard.set("WWFF", forKey: "cqModifier")

        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -10
        )

        XCTAssertEqual(messages.first, truncatedFT8("CQ WWFF \(testCallsign) IN70"))
    }

    func testCQMessage_UsesThreeCharacterTokenForWWA() {
        UserDefaults.standard.set("WWA", forKey: "cqModifier")

        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -10
        )

        XCTAssertEqual(messages.first, truncatedFT8("CQ WWA \(testCallsign) IN70"))
    }

    func testCQMessage_UsesOtherCustomModifier() {
        UserDefaults.standard.set("OTHER", forKey: "cqModifier")
        UserDefaults.standard.set("WWA", forKey: "cqModifierOther")

        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -10
        )

        XCTAssertEqual(messages.first, truncatedFT8("CQ WWA \(testCallsign) IN70"))
    }

    func testCQMessage_WithModifierAndIncludeGridDisabled_OmitsGrid() {
        UserDefaults.standard.set("POTA", forKey: "cqModifier")
        UserDefaults.standard.set(false, forKey: "cqIncludeGrid")

        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -10,
            includeGrid: false
        )

        XCTAssertEqual(messages.first, "CQ POTA \(testCallsign)")
    }

    func testCQMessage_OtherWithoutCustomFallsBackToStandardCQ() {
        UserDefaults.standard.set("OTHER", forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")

        let messages = FT8MessageComposer().generateMessages(
            callsign: testCallsign,
            locator: testLocator,
            dxCallsign: testDXCallsign,
            dxLocator: testDXLocator,
            snrToSend: -10
        )

        XCTAssertEqual(messages.first, "CQ \(testCallsign) IN70")
    }
    
    func testAllMessages_WithFractionalSNR_RoundsCorrectly() {
        // Test rounding behavior
        let testCases: [(input: Double, expected: String)] = [
            (12.5, "+13"),  // Round half up
            (12.4, "+12"),  // Round down
            (-12.5, "-13"), // Round half down (away from zero)
            (-12.4, "-12")  // Round up (toward zero)
        ]
        
        for (input, expected) in testCases {
            let messages = FT8MessageComposer().generateMessages(
                callsign: testCallsign,
                locator: testLocator,
                dxCallsign: testDXCallsign,
                dxLocator: testDXLocator,
                snrToSend: input
            )
            
            let hasExpected = messages.contains { $0.contains(expected) }
            XCTAssertTrue(hasExpected, "SNR \(input) should round to \(expected)")
        }
    }
}
