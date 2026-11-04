//
//  QSOReplyFlowTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 25/09/26.
//
//  Covers the operator reply path (`reply(to:)`) and the shared QSO start
//  helper used by the automatic path (`handleRXAction`). Offline, no audio.
//

import XCTest
@testable import ft8_ham

@MainActor
final class QSOReplyFlowTests: XCTestCase {

    private var viewModel: FT8ViewModel!
    private var savedDefaults: [String: Any?] = [:]

    private let myCall = "EA4XYZ"
    private let dxCall = "K1ABC"

    /// @AppStorage keys these tests write. Restored in tearDown.
    private let touchedKeys = [
        "callsign", "locator", "autoSequencingEnabled", "holdTXFrequency", "evenCycle"
    ]

    override func setUp() async throws {
        try await super.setUp()
        for key in touchedKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        viewModel = FT8ViewModel(
            audioManager: MockAudioManager(),
            engine: MockMessageDecoder(),
            logbookManager: MockLogbookManager()
        )
        viewModel.callsign = myCall
        viewModel.locator = "IN80"
        viewModel.holdTXFrequency = false
    }

    override func tearDown() async throws {
        if viewModel.transmitLoopActive { viewModel.toggleTransmit() }
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        savedDefaults = [:]
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Seconds 0 to 14 of a minute are the even FT8 cycle, 15 to 29 the odd one.
    private func timestamp(even: Bool) -> Date {
        Date(timeIntervalSinceReferenceDate: even ? 30 : 45)
    }

    private func message(_ text: String, even: Bool = true, frequency: Double = 1200) -> FT8Message {
        FT8Message(
            text: text,
            mode: .ft8,
            isRealtime: true,
            timestamp: timestamp(even: even),
            measuredSNR: -8,
            frequency: frequency,
            band: .band20m
        )
    }

    // MARK: - autoSequencingEnabled is a user setting

    func testReply_doesNotEnableAutoSequencing() {
        viewModel.autoSequencingEnabled = false

        viewModel.reply(to: message("CQ \(dxCall) FN31"))

        XCTAssertFalse(viewModel.autoSequencingEnabled,
                       "Replying must not turn auto-sequencing on")
        XCTAssertTrue(viewModel.transmitLoopActive, "The reply itself still starts TX")
    }

    func testReply_doesNotDisableAutoSequencing() {
        viewModel.autoSequencingEnabled = true

        viewModel.reply(to: message("CQ \(dxCall) FN31"))

        XCTAssertTrue(viewModel.autoSequencingEnabled)
    }

    // MARK: - The QSO manager's action is honored

    func testReplyToCQ_selectsGridMessage() {
        viewModel.reply(to: message("CQ \(dxCall) FN31"))

        XCTAssertEqual(viewModel.selectedMessageIndex, FT8ViewModel.TXMessageIndex.grid)
        XCTAssertEqual(viewModel.dxCallsign, dxCall)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingGrid(dxCallsign: dxCall))
    }

    func testReplyToGridAddressedToMe_selectsReportMessage() {
        viewModel.reply(to: message("\(myCall) \(dxCall) FN31"))

        XCTAssertEqual(viewModel.selectedMessageIndex, FT8ViewModel.TXMessageIndex.report,
                       "A station that already sent me its grid gets my report (TX2)")
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingReport(dxCallsign: dxCall))
        XCTAssertTrue(viewModel.transmitLoopActive)
        XCTAssertTrue(viewModel.isReadyForTX)
    }

    func testReplyToReportAddressedToMe_selectsRReportMessage() {
        viewModel.reply(to: message("\(myCall) \(dxCall) -07"))

        XCTAssertEqual(viewModel.selectedMessageIndex, FT8ViewModel.TXMessageIndex.rReport,
                       "Tapping a report sent to me answers it (TX3), not with my grid again")
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sendingRReport(dxCallsign: dxCall))
        XCTAssertTrue(viewModel.transmitLoopActive)
    }

    func testReplyToRReportAddressedToMe_selectsRR73Message() {
        viewModel.reply(to: message("\(myCall) \(dxCall) R-07"))

        XCTAssertEqual(viewModel.selectedMessageIndex, FT8ViewModel.TXMessageIndex.rr73)
        XCTAssertEqual(viewModel.qsoManager.qsoState, .sending73(dxCallsign: dxCall))
    }

    func testReplyToOwnCallsign_isIgnoredAndDoesNotStartTX() {
        XCTAssertFalse(viewModel.transmitLoopActive)

        viewModel.reply(to: message("CQ \(myCall) IN80"))

        XCTAssertFalse(viewModel.transmitLoopActive, ".ignore must not start the TX loop")
        XCTAssertFalse(viewModel.isReadyForTX)
        XCTAssertEqual(viewModel.dxCallsign, "", "No QSO may be locked with my own call")
        XCTAssertNil(viewModel.toast)
    }

    func testStartReply_ownCallsign_returnsIgnore() {
        let action = viewModel.qsoManager.startReply(
            to: message("CQ \(myCall) IN80"),
            myCallsign: myCall.lowercased(),
            myLocator: "IN80"
        )
        XCTAssertEqual(action, .ignore)
        XCTAssertEqual(viewModel.qsoManager.lockedDXCallsign, "")
    }

    // MARK: - Guard

    func testReply_blockedWhenSettingsNotLoaded() {
        viewModel.callsign = ""
        XCTAssertFalse(viewModel.settingsLoaded)

        viewModel.reply(to: message("CQ \(dxCall) FN31"))

        XCTAssertFalse(viewModel.transmitLoopActive)
        XCTAssertEqual(viewModel.dxCallsign, "")
        XCTAssertEqual(viewModel.qsoManager.qsoState, .idle)
    }

    func testReply_blockedWhenLocatorInvalid() {
        viewModel.locator = "XX"
        XCTAssertFalse(viewModel.settingsLoaded)

        viewModel.reply(to: message("CQ \(dxCall) FN31"))

        XCTAssertFalse(viewModel.transmitLoopActive)
        XCTAssertEqual(viewModel.dxCallsign, "")
    }

    // MARK: - Slot and frequency come from the same DX message

    func testReply_slotAndFrequencyFromTappedMessage() {
        viewModel.frequency = 2500

        viewModel.reply(to: message("CQ \(dxCall) FN31", even: true, frequency: 1200))

        XCTAssertEqual(viewModel.frequency, 1200)
        XCTAssertEqual(viewModel.txSlotPreference, .forceOdd)
        XCTAssertFalse(viewModel.evenCycle, "DX on even means I transmit on odd")
    }

    func testAutoSendGrid_slotAndFrequencyFromDXMessage_notFromLastDecode() {
        viewModel.frequency = 2500
        // DX called CQ on the even cycle at 1200 Hz ...
        let dxCQ = message("CQ \(dxCall) FN31", even: true, frequency: 1200)
        // ... and a different station was decoded after it on the odd cycle.
        let other = message("CQ DL1XYZ JO31", even: false, frequency: 1800)
        viewModel.receivedMessages = [dxCQ, other]

        viewModel.handleRXAction(.sendGrid(dxCallsign: dxCall, dxLocator: "FN31"))

        XCTAssertEqual(viewModel.frequency, 1200, "Frequency comes from the DX message")
        XCTAssertEqual(viewModel.txSlotPreference, .forceOdd,
                       "Slot comes from the DX message, not the last decode")
        XCTAssertFalse(viewModel.evenCycle)
    }

    func testAutoSendReport_slotFromDXMessage_keepsFrequency() {
        viewModel.frequency = 2500
        let dxGrid = message("\(myCall) \(dxCall) FN31", even: false, frequency: 900)
        let other = message("CQ DL1XYZ JO31", even: true, frequency: 1800)
        viewModel.receivedMessages = [dxGrid, other]

        viewModel.handleRXAction(.sendReport(dxCallsign: dxCall, report: -8))

        XCTAssertEqual(viewModel.selectedMessageIndex, FT8ViewModel.TXMessageIndex.report)
        XCTAssertEqual(viewModel.txSlotPreference, .forceEven,
                       "DX on odd means I transmit on even")
        XCTAssertTrue(viewModel.evenCycle)
        XCTAssertEqual(viewModel.frequency, 2500,
                       "The automatic path keeps my TX frequency mid-exchange")
    }

    // MARK: - Toast

    func testReply_showsReplyingToast() {
        viewModel.reply(to: message("CQ \(dxCall) FN31"))

        let toast = viewModel.toast
        XCTAssertNotNil(toast)
        XCTAssertEqual(toast?.duration, ToastMessage.defaultDuration)
        XCTAssertTrue(toast?.message.contains(dxCall) ?? false)
    }

    func testReply_noToastWhenStationAlreadyLocked() {
        viewModel.reply(to: message("CQ \(dxCall) FN31"))
        viewModel.toast = nil

        viewModel.reply(to: message("CQ \(dxCall) FN31"))

        XCTAssertNil(viewModel.toast, "Tapping the current DX again must not toast")
    }

    func testAutomaticPath_neverToasts() {
        viewModel.receivedMessages = [message("CQ \(dxCall) FN31")]

        viewModel.handleRXAction(.sendGrid(dxCallsign: dxCall, dxLocator: "FN31"))

        XCTAssertNil(viewModel.toast)
    }
}
