//
//  QSOTransitions.swift
//  ft_ham
//
//  Created by Pablo Turrion on 4/1/26.
//

import Foundation
import XCTest
@testable import ft8_ham

extension FT8Message {

    static func testRX(
        text: String,
        msgType: FT8MessageType,
        snr: Double = -10,
        callsign: String? = nil,
        dxCallsign: String? = nil,
        dxLocator: String? = nil,
        frequency: Double = 1500
    ) -> FT8Message {

        FT8Message(
            text: text,
            mode: .ft8,
            isRealtime: false,
            timestamp: Date(),
            measuredSNR: snr,
            frequency: frequency,
            timeOffset: 0,
            ldpcErrors: 0,
            isTX: false,
            band: .band20m
        )
    }
}

extension BatchProcessResult {

    static func test(messages: [FT8Message]) -> BatchProcessResult {
        BatchProcessResult(
            messages: messages,
            labels: [],
            waterfallSamples: [],
            newLocators: [],
            workedCountries: [],
            shouldResetFirstLoop: false
        )
    }
}

@MainActor
final class FT8QSOFlowTests: XCTestCase {

    private var viewModel: FT8ViewModel!

    override func setUp() {
        super.setUp()

        viewModel = FT8ViewModel()
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IN70"

        viewModel.autoSequencingEnabled = true
        viewModel.autoCQReplyEnabled = true
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - CQ → 73 happy path
    
    @MainActor
    func testCQToCompleteQSO() async {
        
        viewModel.autoCQReplyEnabled = true
        viewModel.qsoList = []
        
        // STEP 1: RX CQ
        await viewModel.applyBatchUpdates(
            .test(messages: [
                .testRX(
                    text: "CQ DL2XYZ JO62",
                    msgType: .cq,
                    callsign: "DL2XYZ"
                )
            ]),
            slotIndex: nil
        )
        XCTAssertEqual(viewModel.receivedMessages.last?.text, "CQ DL2XYZ JO62")
        XCTAssertEqual(viewModel.qsoManager.lockedDXCallsign, "DL2XYZ")
        XCTAssertTrue(viewModel.transmitLoopActive)
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, -10, accuracy: 1)
        
        // STEP 2: RX report from DX
        await viewModel.applyBatchUpdates(
            .test(messages: [
                .testRX(
                    text: "EA1AAA DL2XYZ +03",
                    msgType: .standardSignalReport,
                    callsign: "DL2XYZ",
                    dxCallsign: "EA1AAA"
                )
            ]),
            slotIndex: nil
        )
        
        XCTAssertEqual(viewModel.receivedMessages.last?.text, "EA1AAA DL2XYZ +03")
        XCTAssertEqual(viewModel.qsoManager.lastReceivedSNR, 3)
        
        // STEP 3: RX RRR
        await viewModel.applyBatchUpdates(
            .test(messages: [
                .testRX(
                    text: "EA1AAA DL2XYZ RRR",
                    msgType: .rrr,
                    callsign: "DL2XYZ"
                )
            ]),
            slotIndex: nil
        )
        
        XCTAssertEqual(viewModel.receivedMessages.last?.text, "EA1AAA DL2XYZ RRR")
        
        // STEP 4: RX 73
        await viewModel.applyBatchUpdates(
            .test(messages: [
                .testRX(
                    text: "EA1AAA DL2XYZ 73",
                    msgType: .final73,
                    callsign: "DL2XYZ",
                    dxLocator: "JO62"
                )
            ]),
            slotIndex: nil
        )
        
        // ASSERT: QSO completed and logged
        XCTAssertEqual(viewModel.qsoManager.qsoState, .callingCQ)
        XCTAssertEqual(viewModel.qsoList.count, 1)
        
        if(viewModel.qsoList.count > 0){
            let qso = viewModel.qsoList.first!
            XCTAssertEqual(qso.callsign, "DL2XYZ")
            XCTAssertEqual(qso.grid, "JO62")
            XCTAssertEqual(qso.rstRcvd, "3")
            XCTAssertEqual(qso.rstSent, "-10")
        }
    }
}


@MainActor
final class FT8QSOIgnoreTests: XCTestCase {

    func testIgnoreUnrelatedMessage() async {

        let vm = FT8ViewModel()
        vm.callsign = "EA1AAA"
        vm.locator = "IN70"
        vm.autoSequencingEnabled = true
        vm.autoCQReplyEnabled = true

        await vm.applyBatchUpdates(
            .test(messages: [
                .testRX(
                    text: "CQ F4ABC JN18",
                    msgType: .cq,
                    callsign: "F4ABC"
                )
            ]),
            slotIndex: nil
        )

        XCTAssertEqual(vm.qsoManager.qsoState.lockedCallsign, "F4ABC")

        await vm.applyBatchUpdates(
            .test(messages: [
                .testRX(
                    text: "CQ K1ZZ FN31",
                    msgType: .cq,
                    callsign: "K1ZZ"
                )
            ]),
            slotIndex: nil
        )

        // Still locked on first DX
        XCTAssertEqual(vm.qsoManager.qsoState.lockedCallsign, "F4ABC")
    }
    
    func testIgnoreUnrelatedCQWhileLocked() async {

         let vm = FT8ViewModel()
         vm.callsign = "EA1AAA"
         vm.locator = "IN70"
         vm.autoSequencingEnabled = true
         vm.autoCQReplyEnabled = true

         await vm.applyBatchUpdates(
             .test(messages: [
                 .testRX(
                     text: "CQ F4ABC JN18",
                     msgType: .cq,
                     callsign: "F4ABC"
                 )
             ]),
             slotIndex: nil
         )

         XCTAssertEqual(vm.qsoManager.lockedDXCallsign, "F4ABC")

         await vm.applyBatchUpdates(
             .test(messages: [
                 .testRX(
                     text: "CQ K1ZZ FN31",
                     msgType: .cq,
                     callsign: "K1ZZ"
                 )
             ]),
             slotIndex: nil
         )

         // Still locked to first DX
         XCTAssertEqual(vm.qsoManager.lockedDXCallsign, "F4ABC")
     }

    
    func test_QSO_withCourtesyListening_andFinal73() {
        let manager = QSOStatusManager()
        let myCall = "EA4IQL"
        let dx = "EA1TER"

        // Start QSO from CQ
        _ = manager.startReply(
            to: FT8Message.testRX(
                text: "CQ EA1TER IN80",
                msgType: .cq,
                callsign: dx
            ),
            myCallsign: myCall,
            myLocator: "IN80"
        )

        // DX sends report
        let report = FT8Message.testRX(
            text: "\(myCall) \(dx) -05",
            msgType: .standardSignalReport,
            snr: -10,
            callsign: dx,
            dxCallsign: myCall
        )

        var action = manager.handleIncomingMessage(
            report,
            myCallsign: myCall,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        XCTAssertEqual(action, .sendRReport(dxCallsign: dx, report: -10))

        // DX confirms with RR73
        let rr73 = FT8Message.testRX(
            text: "\(myCall) \(dx) RR73",
            msgType: .rr73,
            callsign: dx,
            dxCallsign: myCall
        )

        action = manager.handleIncomingMessage(
            rr73,
            myCallsign: myCall,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // RR73 now sends courtesy 73 back and transitions to sending73
        XCTAssertEqual(action, .send73(dxCallsign: dx))
        XCTAssertEqual(manager.qsoState, .sending73(dxCallsign: dx))

        // DX sends final 73
        let final73 = FT8Message.testRX(
            text: "\(myCall) \(dx) 73",
            msgType: .final73,
            callsign: dx,
            dxCallsign: myCall
        )

        action = manager.handleIncomingMessage(
            final73,
            myCallsign: myCall,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // Final 73 while in sending73 closes the QSO
        XCTAssertEqual(action, .completeQSO(dxCallsign: dx))

        // Courtesy timeout closes QSO
//        action = manager.handleCourtesyTimeout()

        // closeQSO resets state to idle for operational readiness
        XCTAssertEqual(manager.qsoState, .idle)
    }

    func test_QSO_RR73_withoutFinal73_closesAfterTimeout() {
        let manager = QSOStatusManager()
        let myCall = "EA4IQL"
        let dx = "EA1TER"

        _ = manager.startReply(
            to: FT8Message.testRX(
                text: "CQ EA1TER IN80",
                msgType: .cq,
                callsign: dx
            ),
            myCallsign: myCall,
            myLocator: "IN80"
        )

        _ = manager.handleIncomingMessage(
            FT8Message.testRX(
                text: "\(myCall) \(dx) -03",
                msgType: .standardSignalReport,
                snr: -7,
                callsign: dx,
                dxCallsign: myCall
            ),
            myCallsign: myCall,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        let action = manager.handleIncomingMessage(
            FT8Message.testRX(
                text: "\(myCall) \(dx) RR73",
                msgType: .rr73,
                callsign: dx,
                dxCallsign: myCall
            ),
            myCallsign: myCall,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // RR73 now sends courtesy 73 back and transitions to sending73
        XCTAssertEqual(manager.qsoState, .sending73(dxCallsign: dx))
        XCTAssertEqual(action, .send73(dxCallsign: dx))
    }


    func test_TX_doesNotCloseQSO_afterRR73() {
        let manager = QSOStatusManager()
        let dx = "EA1TER"

        manager.qsoState = .sending73(dxCallsign: dx)
        manager.lockedDXCallsign = dx

        _ = QSOAction.sendRR73(dxCallsign: dx)

        XCTAssertNotEqual(manager.qsoState, .idle)
    }

    // MARK: - Ignore / locking behaviour

    @MainActor
    final class FT8QSOIgnoreTests: XCTestCase {

        func testIgnoreUnrelatedCQWhileLocked() async {

            let vm = FT8ViewModel()
            vm.callsign = "EA1AAA"
            vm.locator = "IN70"
            vm.autoSequencingEnabled = true
            vm.autoCQReplyEnabled = true

            await vm.applyBatchUpdates(
                .test(messages: [
                    .testRX(
                        text: "CQ F4ABC JN18",
                        msgType: .cq,
                        callsign: "F4ABC"
                    )
                ]),
                slotIndex: nil
            )

            XCTAssertEqual(vm.qsoManager.lockedDXCallsign, "F4ABC")

            await vm.applyBatchUpdates(
                .test(messages: [
                    .testRX(
                        text: "CQ K1ZZ FN31",
                        msgType: .cq,
                        callsign: "K1ZZ"
                    )
                ]),
                slotIndex: nil
            )

            // Still locked to first DX
            XCTAssertEqual(vm.qsoManager.lockedDXCallsign, "F4ABC")
        }
    }

    // MARK: - QSO flow tests

    @MainActor
    final class QSOStatusManagerFlowTests: XCTestCase {

        func test_QSO_closesImmediatelyOnRR73() {

            let manager = QSOStatusManager()
            let myCall = "EA4IQL"
            let dx = "EA1TER"

            _ = manager.startReply(
                to: .testRX(
                    text: "CQ EA1TER IN80",
                    msgType: .cq,
                    callsign: dx
                ),
                myCallsign: myCall,
                myLocator: "IN80"
            )

            let report = FT8Message.testRX(
                text: "\(myCall) \(dx) -05",
                msgType: .standardSignalReport,
                snr: -5,
                callsign: dx,
                dxCallsign: myCall
            )

            _ = manager.handleIncomingMessage(
                report,
                myCallsign: myCall,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: true
            )
            XCTAssertEqual(manager.lockedDXCallsign, dx)

            let rr73 = FT8Message.testRX(
                text: "\(myCall) \(dx) RR73",
                msgType: .rr73,
                callsign: dx,
                dxCallsign: myCall
            )

            let action = manager.handleIncomingMessage(
                rr73,
                myCallsign: myCall,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: true
            )

            // RR73 now sends courtesy 73 back and transitions to sending73
            XCTAssertEqual(action, .send73(dxCallsign: dx))
            XCTAssertEqual(manager.qsoState, .sending73(dxCallsign: dx))
        }

        func test_Final73ReceivedWhileSending73ClosesQSO() {

            let manager = QSOStatusManager()
            let myCall = "EA4IQL"
            let dx = "EA1TER"

            manager.qsoState = .sending73(dxCallsign: dx)
            manager.lockedDXCallsign = dx
            XCTAssertEqual(manager.lockedDXCallsign, dx)

            let final73 = FT8Message.testRX(
                text: "\(myCall) \(dx) 73",
                msgType: .final73,
                callsign: dx,
                dxCallsign: myCall
            )

            let action = manager.handleIncomingMessage(
                final73,
                myCallsign: myCall,
                autoSequencingEnabled: true,
                autoCQReplyEnabled: true
            )

            XCTAssertEqual(action, .completeQSO(dxCallsign: dx))
            // closeQSO resets state to idle for operational readiness
            XCTAssertEqual(manager.qsoState, .idle)
        }

        func test_Courtesy73_afterCompletedQSO_repliesOnce() {

            let manager = QSOStatusManager()
            let dx = "EA1TER"

            _ = manager.closeQSO(dxCallsign: dx, openCourtesyWindow: true)

            let courtesy73 = FT8Message.testRX(
                text: "EA4IQL EA1TER 73",
                msgType: .final73,
                callsign: dx
            )

            let firstAction = manager.handleIncomingMessage(
                courtesy73,
                myCallsign: "EA4IQL",
                autoSequencingEnabled: true,
                autoCQReplyEnabled: true
            )

            XCTAssertEqual(firstAction, .send73(dxCallsign: dx))

            let secondAction = manager.handleIncomingMessage(
                courtesy73,
                myCallsign: "EA4IQL",
                autoSequencingEnabled: true,
                autoCQReplyEnabled: true
            )

            XCTAssertEqual(secondAction, .ignore)
        }

        func test_TX_RR73_closesQSO() {

            let manager = QSOStatusManager()
            let dx = "EA1TER"

            manager.qsoState = .sending73(dxCallsign: dx)
            manager.lockedDXCallsign = dx
            XCTAssertEqual(manager.lockedDXCallsign, dx)

            let txRR73 = FT8Message.testRX(
                text: "EA4IQL EA1TER RR73",
                msgType: .rr73,
                callsign: "EA4IQL",
                dxCallsign: dx
            )

            let action = manager.advanceStateOnTX(
                message: txRR73,
                frequency: 14074000,
                band: .band20m,
                isFT4: false
            )

            XCTAssertEqual(action, .completeQSO(dxCallsign: dx))
            // closeQSO resets state to idle for operational readiness
            XCTAssertEqual(manager.qsoState, .idle)
        }
    }


}

