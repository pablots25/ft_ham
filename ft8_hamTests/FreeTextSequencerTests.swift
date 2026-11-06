//
//  FreeTextSequencerTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

@MainActor
final class FreeTextSequencerTests: XCTestCase {

    private var viewModel: FT8ViewModel!
    private var decoder: MockMessageDecoder!
    private var savedDefaults: [String: Any?] = [:]

    override func setUp() async throws {
        try await super.setUp()
        for key in ["callsign", "locator", "freeTextMessage", "evenCycle"] {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        UserDefaults.standard.set("EA4IQL", forKey: "callsign")
        UserDefaults.standard.set("IN80", forKey: "locator")

        decoder = MockMessageDecoder()
        viewModel = FT8ViewModel(audioManager: MockAudioManager(), engine: decoder)
        viewModel.applicationState = { .active }
        viewModel.callsign = "EA4IQL"
        viewModel.locator = "IN80"
        viewModel.freeTextMessage = "TNX 73 GL"
        viewModel.txSlotPreference = .forceEven
    }

    override func tearDown() async throws {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        viewModel = nil
        try await super.tearDown()
    }

    private func slot(even: Bool) -> SlotInfo {
        SlotInfo(startTime: Date(), slotIndex: even ? 10 : 11, isEven: even, isFT4: false)
    }

    // MARK: - determineAction

    func test_determineAction_freeTextLoop_transmitsOnMyParityOnly() {
        viewModel.freeTextLoopActive = true
        XCTAssertEqual(viewModel.determineAction(for: slot(even: true)), .transmit)
        XCTAssertEqual(viewModel.determineAction(for: slot(even: false)), .receive)
    }

    func test_determineAction_freeTextLoop_ignoresQSOState() {
        // No CQ loop, idle QSO state: the QSO path would never transmit.
        viewModel.transmitLoopActive = false
        XCTAssertEqual(viewModel.determineAction(for: slot(even: true)), .receive)
        viewModel.freeTextLoopActive = true
        XCTAssertEqual(viewModel.determineAction(for: slot(even: true)), .transmit)
    }

    // MARK: - Loop exclusivity

    func test_toggleTransmit_disablesFreeTextLoop() {
        viewModel.freeTextLoopActive = true
        viewModel.toggleTransmit()
        XCTAssertTrue(viewModel.transmitLoopActive)
        XCTAssertFalse(viewModel.freeTextLoopActive)
    }

    func test_startFreeTextLoop_disablesQSOLoop() {
        viewModel.transmitLoopActive = true
        viewModel.startFreeTextLoop()
        XCTAssertTrue(viewModel.freeTextLoopActive)
        XCTAssertFalse(viewModel.transmitLoopActive)
    }

    func test_startFreeTextLoop_refusesInvalidText() {
        viewModel.freeTextMessage = ""
        XCTAssertFalse(viewModel.canStartFreeTextLoop)
        viewModel.startFreeTextLoop()
        XCTAssertFalse(viewModel.freeTextLoopActive)
    }

    func test_stopCurrentTX_disablesFreeTextLoop() {
        viewModel.freeTextLoopActive = true
        viewModel.stopCurrentTX()
        XCTAssertFalse(viewModel.freeTextLoopActive)
    }

    // MARK: - performTransmission

    /// Audio started in the background has no IO cycle and crashes the player node.
    func test_performTransmission_inBackground_doesNotStartTheTX() async {
        viewModel.applicationState = { .background }
        viewModel.freeTextLoopActive = true

        await viewModel.performTransmission(slot: slot(even: true))

        XCTAssertNil(viewModel.activeTXMessage)
        XCTAssertFalse(viewModel.activeTXIsFreeText)
    }

    func test_performTransmission_freeText_usesFreeTextEncoderAndSkipsQSOAdvance() async {
        viewModel.freeTextLoopActive = true
        let s = slot(even: true)

        await viewModel.performTransmission(slot: s)

        XCTAssertEqual(decoder.generateFreeTextCallCount, 1)
        XCTAssertEqual(decoder.lastGeneratedFreeText, "TNX 73 GL")
        XCTAssertEqual(decoder.generateFT8CallCount, 0)
        XCTAssertEqual(viewModel.transmittedMessages.last?.text, "TNX 73 GL")
        XCTAssertTrue(viewModel.transmittedMessages.last?.isTX ?? false)
        XCTAssertTrue(viewModel.activeTXIsFreeText)

        // Finishing the audio must not touch the QSO state machine.
        let stateBefore = viewModel.qsoManager.qsoState
        viewModel.handleTXDidFinishFromAudioManager()
        XCTAssertEqual(viewModel.qsoManager.qsoState, stateBefore)
        XCTAssertFalse(viewModel.activeTXIsFreeText)
        XCTAssertNil(viewModel.activeTXMessage)
    }
}
