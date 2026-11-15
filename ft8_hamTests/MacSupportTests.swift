//
//  MacSupportTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/11/26.
//
//  The Mac ("Designed for iPad") additions: background policy, menu bar
//  commands, platform copy, audio device names, decoded row menu and the
//  waterfall display scale.
//

import XCTest
@testable import ft8_ham

// MARK: - Background policy

final class BackgroundOperationPolicyTests: XCTestCase {

    func test_keepsRadioRunning_onlyOnAMacWithTheFlagOn() {
        XCTAssertTrue(BackgroundOperationPolicy.keepsRadioRunning(isMac: true, flagEnabled: true))
        XCTAssertFalse(BackgroundOperationPolicy.keepsRadioRunning(isMac: true, flagEnabled: false))
        XCTAssertFalse(BackgroundOperationPolicy.keepsRadioRunning(isMac: false, flagEnabled: true))
        XCTAssertFalse(BackgroundOperationPolicy.keepsRadioRunning(isMac: false, flagEnabled: false))
    }

    func test_macBackgroundOperationFlag_shipsOff() {
        XCTAssertFalse(FeatureFlag.macBackgroundOperation.defaultValue)
        XCTAssertEqual(FeatureFlag.macBackgroundOperation.rawValue, "macBackgroundOperation")
    }
}

// MARK: - Radio commands

final class RadioCommandAvailabilityTests: XCTestCase {

    func test_nothingRuns_beforeTheStationIsConfigured() {
        let state = RadioCommandAvailability(
            settingsLoaded: false, isListening: true, isTransmitting: true,
            transmitLoopActive: true, freeTextLoopActive: true
        )
        XCTAssertFalse(state.canToggleRX)
        XCTAssertFalse(state.canToggleAutoTX)
        XCTAssertFalse(state.canStopTX)
        XCTAssertFalse(state.canStopAll)
    }

    func test_stopTX_needsATransmissionInProgress() {
        var state = RadioCommandAvailability(settingsLoaded: true)
        XCTAssertFalse(state.canStopTX)
        state.isTransmitting = true
        XCTAssertTrue(state.canStopTX)
    }

    func test_stopAll_needsSomethingRunning() {
        let idle = RadioCommandAvailability(settingsLoaded: true)
        XCTAssertFalse(idle.canStopAll)
        XCTAssertTrue(RadioCommandAvailability(settingsLoaded: true, isListening: true).canStopAll)
        XCTAssertTrue(RadioCommandAvailability(settingsLoaded: true, isTransmitting: true).canStopAll)
        XCTAssertTrue(RadioCommandAvailability(settingsLoaded: true, transmitLoopActive: true).canStopAll)
        XCTAssertTrue(RadioCommandAvailability(settingsLoaded: true, freeTextLoopActive: true).canStopAll)
    }

    func test_toggles_areAvailableOnceConfigured() {
        let state = RadioCommandAvailability(settingsLoaded: true)
        XCTAssertTrue(state.canToggleRX)
        XCTAssertTrue(state.canToggleAutoTX)
    }

    @MainActor
    func test_model_followsTheViewModel() async {
        let viewModel = FT8ViewModel(audioManager: MockAudioManager(), engine: MockMessageDecoder())
        let model = RadioCommandsModel()
        model.attach(to: viewModel)

        viewModel.rootState.settingsLoaded = true
        viewModel.isListening = true
        viewModel.transmitLoopActive = true

        // The model republishes on the next run loop turn.
        let expectation = expectation(description: "availability updated")
        let cancellable = model.$availability
            .first { $0.settingsLoaded && $0.isListening && $0.transmitLoopActive }
            .sink { _ in expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 2)
        cancellable.cancel()

        XCTAssertTrue(model.availability.canStopAll)
        XCTAssertFalse(model.availability.canStopTX)
    }
}

// MARK: - Platform copy

final class ReplyGuidanceTests: XCTestCase {

    func test_iPhoneAndIPad_keepTheSwipeCopy() {
        for gesture in ReplyTapGesture.allCases {
            XCTAssertEqual(ReplyGuidance.tutorialText(isMac: false, gesture: gesture).key, "tutorial_swipe_reply")
            XCTAssertEqual(ReplyGuidance.legendTitle(isMac: false, gesture: gesture).key, "Swipe right to reply")
            XCTAssertEqual(ReplyGuidance.legendSymbol(isMac: false, gesture: gesture), "chevron.right.2")
        }
    }

    func test_mac_followsTheReplyGesture() {
        XCTAssertEqual(
            ReplyGuidance.tutorialText(isMac: true, gesture: .single).key,
            "Click any received message to reply on the frequency it used."
        )
        XCTAssertEqual(
            ReplyGuidance.tutorialText(isMac: true, gesture: .double).key,
            "Double-click any received message to reply on the frequency it used."
        )
        XCTAssertEqual(ReplyGuidance.legendTitle(isMac: true, gesture: .single).key, "Click to reply")
        XCTAssertEqual(ReplyGuidance.legendTitle(isMac: true, gesture: .double).key, "Double-click to reply")
        XCTAssertEqual(ReplyGuidance.legendSymbol(isMac: true, gesture: .double), "cursorarrow.click.2")
    }

    func test_macCopy_neverMentionsSwipesOrVibration() {
        for gesture in ReplyTapGesture.allCases {
            let texts = [
                ReplyGuidance.tutorialText(isMac: true, gesture: gesture).key,
                ReplyGuidance.legendTitle(isMac: true, gesture: gesture).key,
                ReplyGuidance.legendDetail(isMac: true, gesture: gesture).key
            ]
            for text in texts {
                XCTAssertFalse(text.localizedCaseInsensitiveContains("swipe"), text)
                XCTAssertFalse(text.localizedCaseInsensitiveContains("vibration"), text)
            }
        }
    }

    func test_storedGesture_readsTheSetting() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ReplyGuidanceTests"))
        defer { defaults.removePersistentDomain(forName: "ReplyGuidanceTests") }
        XCTAssertEqual(ReplyGuidance.storedGesture(defaults), .single)
        defaults.set(ReplyTapGesture.double.rawValue, forKey: "replyTapGesture")
        XCTAssertEqual(ReplyGuidance.storedGesture(defaults), .double)
        defaults.set("bogus", forKey: "replyTapGesture")
        XCTAssertEqual(ReplyGuidance.storedGesture(defaults), .single)
    }
}

final class AudioGuidanceTests: XCTestCase {

    func test_lowVolumeHint_neverShowsOnAMac() {
        XCTAssertFalse(AudioGuidance.showsLowVolumeHint(isMac: true, volume: 0.1))
        XCTAssertFalse(AudioGuidance.showsLowVolumeHint(isMac: true, volume: 1.0))
    }

    func test_lowVolumeHint_onIPhone_followsTheVolume() {
        XCTAssertTrue(AudioGuidance.showsLowVolumeHint(isMac: false, volume: 0.5))
        XCTAssertFalse(AudioGuidance.showsLowVolumeHint(isMac: false, volume: 1.0))
    }

    func test_levelsFootnote_dropsThePhoneVolumeOnAMac() {
        XCTAssertFalse(AudioGuidance.levelsFootnote(isMac: true).key.contains("phone"))
        XCTAssertTrue(AudioGuidance.levelsFootnote(isMac: false).key.contains("phone volume"))
    }
}

// MARK: - Audio device names

final class AudioRouteMonitorTests: XCTestCase {

    func test_displayName_joinsPortNames() {
        XCTAssertEqual(AudioRouteMonitor.displayName(for: ["USB Audio CODEC"]), "USB Audio CODEC")
        XCTAssertEqual(AudioRouteMonitor.displayName(for: ["Left", "Right"]), "Left, Right")
    }

    func test_displayName_isNilWithoutAPort() {
        XCTAssertNil(AudioRouteMonitor.displayName(for: []))
        XCTAssertNil(AudioRouteMonitor.displayName(for: ["  ", ""]))
    }
}

// MARK: - Decoded row menu

final class DecodedMessageMenuItemsTests: XCTestCase {

    func test_cqMessage_offersReplyAndCallsign() {
        let message = FT8Message(text: "CQ EA4IQL IN80", mode: .ft8)
        let items = DecodedMessageMenuItems(message: message, allowReply: true)
        XCTAssertEqual(items.canReply, message.allowsReply)
        XCTAssertEqual(items.callsign, message.callsign?.uppercased())
        XCTAssertEqual(items.messageText, "CQ EA4IQL IN80")
    }

    func test_reply_isHiddenWhenTheListDoesNotAllowIt() {
        let message = FT8Message(text: "CQ EA4IQL IN80", mode: .ft8)
        XCTAssertFalse(DecodedMessageMenuItems(message: message, allowReply: false).canReply)
    }

    func test_ownTransmission_cannotBeRepliedTo() {
        let message = FT8Message(text: "CQ EA4IQL IN80", mode: .ft8, isTX: true)
        XCTAssertFalse(DecodedMessageMenuItems(message: message, allowReply: true).canReply)
    }
}

// MARK: - Waterfall display scale

final class WaterfallDisplayScaleTests: XCTestCase {

    func test_windowScale_winsWhenKnown() {
        XCTAssertEqual(WaterfallRenderView.resolvedScale(windowScale: 1, traitScale: 2), 1)
        XCTAssertEqual(WaterfallRenderView.resolvedScale(windowScale: 2, traitScale: 1), 2)
    }

    func test_fallsBackToTheTraitThenToRetina() {
        XCTAssertEqual(WaterfallRenderView.resolvedScale(windowScale: nil, traitScale: 3), 3)
        XCTAssertEqual(WaterfallRenderView.resolvedScale(windowScale: 0, traitScale: 0), 2)
    }
}
