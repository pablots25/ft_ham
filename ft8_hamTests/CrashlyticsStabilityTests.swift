// CrashlyticsStabilityTests.swift
// ft8_hamTests
//
// Regression tests for the Crashlytics review of September 2026 (1.2.6 in
// production, 1.3.0 on TestFlight).
//
//   1. a315fe8f (variant) — AudioManager.playAudio: scheduleBuffer raised
//      "_outputFormat.channelCount == buffer.format.channelCount" because a
//      failed session activation at launch made init return before the player
//      node was attached. Defence: chain repair before scheduling, plus
//      ObjCExceptionCatcher around scheduleBuffer.
//
//   2. 2344367c — AudioManager.installInputTap: "Failed to initialize active
//      nodes in input chain, err -10868". Defence: ObjCExceptionCatcher around
//      installTap, trying the hardware input format first and the node's
//      output format second (output-first broke RX after route changes in
//      1.3.0 build 15).
//
//   3. Non-fatal noise: suspend/resume lag, and the sanitizer redacting
//      OSStatus codes as callsigns (-10868 showed up as -[CALLSIGN]).

import XCTest
import AVFoundation
@testable import ft8_ham

final class CrashlyticsStabilityTests: XCTestCase {

    private func monoBuffer(frames: AVAudioFrameCount = 1_200) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 12_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return buffer
    }

    // MARK: - 1. scheduleBuffer on a broken playback chain

    func test_playbackChainNeedsRepair_whenPlayerIsDetached() {
        XCTAssertTrue(AudioManager.playbackChainNeedsRepair(
            isAttached: false, playerChannels: 1, bufferChannels: 1))
    }

    func test_playbackChainNeedsRepair_whenChannelCountsDiffer() {
        XCTAssertTrue(AudioManager.playbackChainNeedsRepair(
            isAttached: true, playerChannels: 2, bufferChannels: 1))
    }

    func test_playbackChainNeedsRepair_isFalseForAttachedMonoChain() {
        XCTAssertFalse(AudioManager.playbackChainNeedsRepair(
            isAttached: true, playerChannels: 1, bufferChannels: 1))
    }

    /// The production state: the player node never got attached, so a mono
    /// buffer cannot be scheduled. The repair check must flag it.
    func test_detachedPlayerNode_isFlaggedForRepair() {
        let node = AVAudioPlayerNode()
        let buffer = monoBuffer()

        XCTAssertTrue(AudioManager.playbackChainNeedsRepair(
            isAttached: node.engine != nil,
            playerChannels: node.outputFormat(forBus: 0).channelCount,
            bufferChannels: buffer.format.channelCount))
    }

    /// Scheduling on a detached node raises an NSException. Through the
    /// catcher it must surface as a Swift error instead of a crash.
    func test_scheduleBuffer_onDetachedNode_isCaughtAsErrorNotCrash() {
        let node = AVAudioPlayerNode()
        let buffer = monoBuffer()

        XCTAssertThrowsError(try ObjCExceptionCatcher.catchException {
            node.scheduleBuffer(buffer, completionHandler: nil)
        })
    }

    /// After the repair (attach + mono connection) the chain matches the
    /// buffer and the check no longer asks for a repair.
    func test_repairedChain_matchesMonoBuffer() {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 12_000, channels: 1))

        XCTAssertFalse(AudioManager.playbackChainNeedsRepair(
            isAttached: node.engine != nil,
            playerChannels: node.outputFormat(forBus: 0).channelCount,
            bufferChannels: monoBuffer().format.channelCount))
    }

    // MARK: - 2. Tap format selection

    /// Regression for 1.3.0 (15): after a route change the output side kept
    /// 44.1 kHz while the hardware ran at 48 kHz, and tapping with the output
    /// format failed with "format.sampleRate == inputHWFormat.sampleRate".
    /// The hardware-side input format must be tried first.
    func test_tapFormatCandidates_triesTheInputFormatFirst() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let output = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

        let candidates = AudioManager.tapFormatCandidates(input: input, output: output)

        XCTAssertEqual(candidates.map(\.sampleRate), [48_000, 44_100])
    }

    func test_tapFormatCandidates_dropsADuplicateOutputFormat() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let output = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

        XCTAssertEqual(AudioManager.tapFormatCandidates(input: input, output: output).count, 1)
    }

    func test_tapFormatCandidates_usesTheOutputWhenTheInputIsNotReady() {
        let output = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

        let candidates = AudioManager.tapFormatCandidates(input: AVAudioFormat(), output: output)

        XCTAssertEqual(candidates, [output])
    }

    func test_tapFormatCandidates_isEmptyWhenNeitherFormatIsValid() {
        XCTAssertTrue(AudioManager.tapFormatCandidates(
            input: AVAudioFormat(), output: AVAudioFormat()).isEmpty)
    }

    // MARK: - Recovery in test mode

    @MainActor
    func test_recoverAudioIfNeeded_isANoOpWhenAudioIsDisabled() {
        let sut = AudioManager(waterfallFFTSize: 512, sampleRate: 12_000,
                               initialGain: 1.0, isTestMode: true)
        defer { sut.cleanup() }

        sut.recoverAudioIfNeeded()

        XCTAssertFalse(sut.isListening)
        XCTAssertFalse(sut.wantsMicInput)
    }

    // MARK: - 3a. Lag after suspend/resume

    func test_isSuspensionGap_FT8_wholeSlotLate() {
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 15.5, mode: .ft8))
    }

    func test_isSuspensionGap_FT8_shortLagIsARealStall() {
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 3.0, mode: .ft8))
    }

    func test_isSuspensionGap_FT4_usesTheShorterSlot() {
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 8.0, mode: .ft4))
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 8.0, mode: .ft8))
    }

    /// A slot that started a whole period ago (resume after suspension) and
    /// one that is a few seconds late (a real stall) are both skipped. Only
    /// the log level differs, which `isSuspensionGap` decides.
    @MainActor
    func test_determineAction_skipsLateSlots() {
        let viewModel = FT8ViewModel(audioManager: MockAudioManager(), engine: MockMessageDecoder())

        for lag in [3.0, 15.5] {
            let slot = SlotInfo(startTime: AppClock.now().addingTimeInterval(-lag),
                                slotIndex: 10, isEven: true, mode: .ft8)
            XCTAssertEqual(viewModel.determineAction(for: slot), .skip, "lag \(lag)s")
        }
    }

    // MARK: - 3b. Sanitizer

    private let logger = AppLogger(category: "TEST")

    func test_sanitize_keepsOSStatusCodes() {
        let message = "Failed to start audio engine (com.apple.coreaudio.avfaudio error -10868.)"
        XCTAssertEqual(logger.sanitize(message), message)
    }

    func test_sanitize_keepsPlainNumbers() {
        let message = "Severe system lag detected: 15.497354984283447s. Skipping slot 118140186."
        XCTAssertEqual(logger.sanitize(message), message)
    }

    func test_sanitize_redactsCallsigns() {
        XCTAssertEqual(logger.sanitize("CQ EA4IQL"), "CQ [CALLSIGN]")
        XCTAssertEqual(logger.sanitize("K1ABC 73"), "[CALLSIGN] 73")
    }

    func test_sanitize_redactsGridsAsGrids() {
        XCTAssertEqual(logger.sanitize("Invalid callsign/locator: /IN80"),
                       "Invalid callsign/locator: /[GRID]")
        XCTAssertEqual(logger.sanitize("EA4IQL IN80do"), "[CALLSIGN] [GRID]")
    }
}
