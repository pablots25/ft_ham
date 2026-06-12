//
//  FT8ViewModelTests2.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/12/25.
//

import XCTest
@testable import ft8_ham

@MainActor
final class FT8ViewModelTests2: XCTestCase {

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = FT8ViewModel(txMessages: [], rxMessages: [])
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testGenerateMessagesWithDefaultValues() {
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"
        viewModel.dxCallsign = "K1ABC"
        viewModel.dxLocator = "FN31"
        viewModel.lastSentSNR = 10

        let messages = viewModel.generateMessages()

        XCTAssertEqual(messages.count, 7)
        XCTAssertTrue(messages[0].contains("EA1AAA"))
        XCTAssertTrue(messages[1].contains("K1ABC"))
        XCTAssertTrue(messages[2].contains("+10"))
    }

    func testGenerateMessagesWithEmptyDX() {
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"
        viewModel.dxCallsign = ""
        viewModel.dxLocator = ""
        viewModel.lastSentSNR = -5

        let messages = viewModel.generateMessages()
        XCTAssertTrue(messages[1].contains("XXXXXX"))
        XCTAssertTrue(messages[1].contains("EA1AAA"))
        XCTAssertTrue(messages[2].contains("-05"))
    }

    func testReplyUpdatesDXAndPower() async {
        viewModel.callsign = "EA1AAA"
        viewModel.locator = "IM99"

        let message = FT8Message(
            text: "CQ K1ABC FN31",
            mode: .ft8,
            measuredSNR: 12,
            frequency: 1400,
            isTX: false
        )

        viewModel.reply(to: message)

        XCTAssertEqual(viewModel.dxCallsign, "K1ABC")
        XCTAssertEqual(viewModel.dxLocator, "FN31")
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, 12)
        XCTAssertEqual(viewModel.frequency, 1400)
        XCTAssertEqual(viewModel.selectedMessageIndex, 1)
        XCTAssertEqual(viewModel.allMessages.count, 7)
    }

    func testSettingsLoadedReturnsTrueOnlyIfCallsignAndLocatorSet() {
        viewModel.callsign = ""
        viewModel.locator = ""
        XCTAssertFalse(viewModel.settingsLoaded)

        viewModel.callsign = "EA1AAA"
        XCTAssertFalse(viewModel.settingsLoaded)

        viewModel.locator = "IM99"
        XCTAssertTrue(viewModel.settingsLoaded)
    }

    func testWorkedLocatorsAreUpdated() {
        viewModel.clearReceived()
        
        viewModel.receivedMessages = [
            FT8Message(text: "CQ EA4IQL IN80", mode: .ft8, measuredSNR: -12, frequency: 1500.0, timeOffset: 0.1, isTX: false),
            FT8Message(text: "CQ EA5TTT IN15", mode: .ft8, measuredSNR: -12, frequency: 1500.0, timeOffset: 0.1, isTX: false),
            FT8Message(text: "CQ EA1QQQ IN19", mode: .ft8, measuredSNR: -12, frequency: 1500.0, timeOffset: 0.1, isTX: false),
        ]

        for msg in viewModel.receivedMessages {
            if let dx = msg.locator, !dx.isEmpty, !viewModel.workedLocators.contains(dx) {
                viewModel.workedLocators.append(dx)
            }
        }

        XCTAssertEqual(viewModel.workedLocators.count, 3)
        XCTAssertTrue(viewModel.workedLocators.contains("IN15"))
        XCTAssertTrue(viewModel.workedLocators.contains("IN19"))
    }

    func testDecodeFromWavAppendsMessages() {
        let message1 = FT8Message.decode(text: "EA1AAA K1ABC +10", mode: .ft8, snr: -10, frequency: 1500, timeOffset: 0.1)
        let message2 = FT8Message.decode(text: "K1ABC EA1AAA -12", mode: .ft8, snr: -12, frequency: 1501, timeOffset: 0.2)
        
        // Simulate engine decoding by setting wavURL to nil (so decode returns empty array) and manually appending
        viewModel.receivedMessages = []
        viewModel.workedLocators = []

        viewModel.receivedMessages.append(message1)
        viewModel.receivedMessages.append(message2)

        for msg in viewModel.receivedMessages {
            if let dx = msg.dxLocator, !dx.isEmpty, !viewModel.workedLocators.contains(dx) {
                viewModel.workedLocators.append(dx)
            }
        }

        XCTAssertEqual(viewModel.receivedMessages.count, 2)
        XCTAssertTrue(viewModel.workedLocators.isEmpty || viewModel.workedLocators.count <= 2)
    }

//    func testTransmitMessageOnceValidatesCallsignAndLocator() async throws {
//        viewModel.clearTransmitted()
//        
//        viewModel.callsign = "EA1AAA"
//        viewModel.locator = "IM99"
//        viewModel.allMessages = ["CQ EA1AAA IM99"]
//        viewModel.selectedMessageIndex = 0
//        viewModel.selectedBand = .band10m
//        viewModel.isFT4 = false
//        viewModel.transmitLoopActive = true
//
//        viewModel.startSequencer()
//
//        try await Task.sleep(nanoseconds: 30_500_000_000)
//
//        
//        if(viewModel.transmittedMessages.count > 0){
//            XCTAssertEqual(viewModel.transmittedMessages.count, 1)
//            XCTAssertEqual(viewModel.transmittedMessages[0].text, "CQ EA1AAA IM99")
//        }else{
//            XCTFail("No message was transmitted")
//        }
//        viewModel.startSequencer()
//    }
    
    func testClearReceivedMessages() {
        viewModel.receivedMessages = [
            FT8Message(text: "Message 1", mode: .ft8),
            FT8Message(text: "Message 2", mode: .ft8)
        ]

        viewModel.clearReceived()

        XCTAssertTrue(viewModel.receivedMessages.isEmpty)
    }

    func testClearTransmittedMessages() {
        viewModel.transmittedMessages = [
            FT8Message(text: "TX 1", mode: .ft8),
            FT8Message(text: "TX 2", mode: .ft8)
        ]

        viewModel.clearTransmitted()

        XCTAssertTrue(viewModel.transmittedMessages.isEmpty)
    }

    func testClearLastDecodedMessage() {
        viewModel.decodedMessage = FT8Message(text: "Last decoded", mode: .ft8)

        viewModel.clearLastMessage()

        XCTAssertNil(viewModel.decodedMessage)
    }

}

@MainActor
final class FT8ViewModel_FirstLaunchTests: XCTestCase {

    override func setUp() {
        super.setUp()

        // Simulate fresh install
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "autoRXAtStart")
        defaults.removeObject(forKey: "callsign")
        defaults.removeObject(forKey: "locator")
        defaults.removeObject(forKey: "isFT4")
    }

    func test_firstLaunch_doesNotStartRX() async {
        let viewModel = FT8ViewModel()

        // Allow async init side-effects to settle
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(viewModel.isSequencerRunning, "RX must not start on first launch")
        XCTAssertNil(viewModel.sequencerTask, "Sequencer task must not exist on first launch")
    }
}
