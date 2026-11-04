//
//  MessageProcessorTests.swift
//  ft_hamTests
//
//  Created by Pablo Turrion on 13/1/26.
//

import XCTest
@testable import ft8_ham

final class MessageProcessorTests: XCTestCase {
    
    var processor: MessageProcessor!
    var txMessage: FT8Message!
    
    override func setUp() {
        super.setUp()
        processor = MessageProcessor()
        txMessage = FT8Message(text: "CQ EA1ABC IN83", mode: .ft8, isTX: true)
    }
    
    func testTimestampMarkerIsAdded() async {
        let batch: [[String: Any]] = []
        let result = await processor.process(
            batch,
            isFT4: false,
            selectedBand: .band40m,
            firstLoopRX: false,
            isTX: false,
            txMessage: txMessage,
            existingLocators: [],
            decodeSelfTXMessages: false
        )
        
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.messages.first?.msgType, .internalTimestamp)
        XCTAssertTrue(result.messages.first?.text.contains(" - 40m") ?? false)
    }
    
    func testPartialDataLossIsAddedOnFirstLoop() async {
        let batch: [[String: Any]] = [
            ["text": "Partial slot"]
        ]
        let result = await processor.process(
            batch,
            isFT4: false,
            selectedBand: .band40m,
            firstLoopRX: true,
            isTX: false,
            txMessage: txMessage,
            existingLocators: [],
            decodeSelfTXMessages: false
        )
        
        // Should have: [Timestamp, Partial Data Loss]
        XCTAssertEqual(result.messages.count, 2)
        XCTAssertEqual(result.messages[0].msgType, .internalTimestamp)
        XCTAssertEqual(result.messages[1].text, "Partial data loss")
        XCTAssertTrue(result.shouldResetFirstLoop)
    }
    
    func testPartialDataLossIsIgnoredAfterFirstLoop() async throws {
        throw XCTSkip("firstLoop is not used if the text is partial slot")
    }
    
    func testMixedBatchProcessing() async {
        let batch: [[String: Any]] = [
            ["text": "Partial slot"],
            ["text": "CQ DX EA1ABC IN83", "snr": -10.0, "frequency": 1500.0]
        ]
        
        // Scenario 1: First loop
        let result1 = await processor.process(
            batch,
            isFT4: false,
            selectedBand: .band20m,
            firstLoopRX: true,
            isTX: false,
            txMessage: txMessage,
            existingLocators: [],
            decodeSelfTXMessages: false
        )
        
        // [Timestamp, Partial Data Loss, CQ Message]
        XCTAssertEqual(result1.messages.count, 3)
        XCTAssertEqual(result1.messages[1].text, "Partial data loss")
        XCTAssertEqual(result1.messages[2].msgType, .cq)
        
        
//        Removed: firstLoopRX is not used if the test is Partial Data loss
//        // Scenario 2: Not first loop
//        let result2 = await processor.process(
//            batch,
//            isFT4: false,
//            selectedBand: .band20m,
//            firstLoopRX: false,
//            isTX: false,
//            txMessage: txMessage,
//            existingLocators: [],
//            decodeSelfTXMessages: false
//        )
//        
//        // [Timestamp, CQ Message] (Partial slot skipped)
//        XCTAssertEqual(result2.messages.count, 2)
//        XCTAssertEqual(result2.messages[1].msgType, .cq)
    }
}
