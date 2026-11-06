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

    /// Regression for 1.3.0 (23): input and output were both rejected after a
    /// route change, so the session's hardware rate is the last candidate.
    func test_tapFormatCandidates_addsTheSessionRateWhenBothSidesAreStale() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let output = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

        let candidates = AudioManager.tapFormatCandidates(
            input: input, output: output, hardwareSampleRate: 48_000)

        XCTAssertEqual(candidates.map(\.sampleRate), [44_100, 48_000])
    }

    func test_tapFormatCandidates_dropsTheSessionRateWhenItMatchesTheInput() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

        let candidates = AudioManager.tapFormatCandidates(
            input: input, output: AVAudioFormat(), hardwareSampleRate: 48_000)

        XCTAssertEqual(candidates, [input])
    }

    func test_tapFormatCandidates_sessionRateKeepsTheInputChannelCount() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

        let candidates = AudioManager.tapFormatCandidates(
            input: input, output: AVAudioFormat(), hardwareSampleRate: 48_000)

        XCTAssertEqual(candidates.last?.sampleRate, 48_000)
        XCTAssertEqual(candidates.last?.channelCount, 2)
    }

    func test_tapFormatCandidates_sessionRateUsesOneChannelWhenTheNodeIsNotReady() {
        let candidates = AudioManager.tapFormatCandidates(
            input: AVAudioFormat(), output: AVAudioFormat(), hardwareSampleRate: 48_000)

        XCTAssertEqual(candidates.map(\.channelCount), [1])
    }

    func test_tapFormatCandidates_ignoresAnInvalidSessionRate() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

        XCTAssertEqual(AudioManager.tapFormatCandidates(
            input: input, output: AVAudioFormat(), hardwareSampleRate: 0), [input])
    }

    // MARK: - Mic tap retry

    @MainActor
    func test_retryMicTap_stopsAtTheFirstSuccess() async {
        var finalFlags: [Bool] = []

        let installed = await AudioManager.retryMicTap(
            delays: [.zero, .zero, .zero],
            sleep: { _ in }
        ) { isFinalAttempt in
            finalFlags.append(isFinalAttempt)
            return finalFlags.count == 2
        }

        XCTAssertTrue(installed)
        XCTAssertEqual(finalFlags, [false, false])
    }

    /// Only the last attempt may record a non-fatal and show a toast.
    @MainActor
    func test_retryMicTap_marksOnlyTheLastAttemptAsFinal() async {
        var finalFlags: [Bool] = []

        let installed = await AudioManager.retryMicTap(
            delays: [.zero, .zero, .zero],
            sleep: { _ in }
        ) { isFinalAttempt in
            finalFlags.append(isFinalAttempt)
            return false
        }

        XCTAssertFalse(installed)
        XCTAssertEqual(finalFlags, [false, false, true])
    }

    @MainActor
    func test_retryMicTap_waitsForEachDelayBeforeItsAttempt() async {
        var events: [String] = []

        _ = await AudioManager.retryMicTap(
            delays: [.milliseconds(1), .milliseconds(2)],
            sleep: { events.append("sleep \($0)") }
        ) { _ in
            events.append("attempt")
            return false
        }

        XCTAssertEqual(events, [
            "sleep \(Duration.milliseconds(1))", "attempt",
            "sleep \(Duration.milliseconds(2))", "attempt"
        ])
    }

    @MainActor
    func test_retryMicTap_makesNoAttemptAfterCancellation() async {
        var attempts = 0

        let installed = await AudioManager.retryMicTap(
            delays: [.zero, .zero],
            sleep: { _ in throw CancellationError() }
        ) { _ in
            attempts += 1
            return true
        }

        XCTAssertFalse(installed)
        XCTAssertEqual(attempts, 0)
    }

    /// RX must come back within the slot after a route change, not a slot later.
    func test_micTapRetryDelays_fitWithinOneFT4Slot() {
        let total = AudioManager.micTapRetryDelays.reduce(Duration.zero, +)

        XCTAssertFalse(AudioManager.micTapRetryDelays.isEmpty)
        XCTAssertLessThan(total, .milliseconds(7_500))
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

    // MARK: - Audio session diagnostics (issue 93f6a2a7)

    private let sessionError = NSError(
        domain: NSOSStatusErrorDomain, code: 561_015_905,
        userInfo: [NSLocalizedDescriptionKey: "Session activation failed"])

    func test_diagnosticDescription_addsDomainCodeAndFourCharacterCode() {
        let error = AudioManagerError.sessionActivationFailed(underlying: sessionError)

        XCTAssertEqual(
            error.diagnosticDescription,
            "Failed to activate audio session: Session activation failed [NSOSStatusErrorDomain 561015905 '!pla']")
    }

    /// The toast groups messages by prefix and must not show the code.
    func test_localizedDescription_doesNotIncludeTheCode() {
        let error = AudioManagerError.sessionActivationFailed(underlying: sessionError)

        XCTAssertEqual(error.localizedDescription,
                       "Failed to activate audio session: Session activation failed")
        XCTAssertEqual(AudioErrorToastText.kind(of: error.localizedDescription), .setup)
    }

    func test_diagnosticDescription_coversEverySessionStep() {
        let errors: [AudioManagerError] = [
            .sessionCategoryConfiguration(underlying: sessionError),
            .sessionModeConfiguration(underlying: sessionError),
            .sessionSampleRateConfiguration(underlying: sessionError),
            .sessionActivationFailed(underlying: sessionError)
        ]

        for error in errors {
            XCTAssertTrue(error.diagnosticDescription.contains("561015905"), "\(error)")
        }
    }

    func test_diagnosticDescription_isThePlainTextWithoutAnUnderlyingError() {
        XCTAssertEqual(AudioManagerError.invalidAudioData.diagnosticDescription,
                       "Invalid audio data size or format")
    }

    func test_diagnosticDescriptionOfRawError_addsTheCode() {
        XCTAssertEqual(
            AudioManagerError.diagnosticDescription(of: sessionError),
            "Session activation failed [NSOSStatusErrorDomain 561015905 '!pla']")
    }

    func test_diagnosticDescriptionOfWrappedError_doesNotRepeatTheCode() {
        let wrapped = AudioManagerError.sessionActivationFailed(underlying: sessionError)

        XCTAssertEqual(AudioManagerError.diagnosticDescription(of: wrapped),
                       wrapped.diagnosticDescription)
    }

    func test_fourCharacterCode_decodesPrintableCodes() {
        XCTAssertEqual(AudioManagerError.fourCharacterCode(561_015_905), "!pla")
    }

    func test_fourCharacterCode_rejectsOtherCodes() {
        XCTAssertNil(AudioManagerError.fourCharacterCode(-10_868))
        XCTAssertNil(AudioManagerError.fourCharacterCode(0))
        XCTAssertNil(AudioManagerError.fourCharacterCode(5))
        XCTAssertNil(AudioManagerError.fourCharacterCode(Int(UInt32.max) + 1))
    }

    func test_sanitize_keepsTheSessionErrorCode() {
        let error = AudioManagerError.sessionActivationFailed(underlying: sessionError)

        XCTAssertEqual(logger.sanitize(error.diagnosticDescription), error.diagnosticDescription)
    }

    func test_activeSessionFailure_reportsTheFirstFailureOfARun() {
        XCTAssertTrue(AudioManager.shouldReportActiveSessionFailure(
            isSessionConfigured: false, alreadyReported: false))
    }

    func test_activeSessionFailure_reportsOncePerRun() {
        XCTAssertFalse(AudioManager.shouldReportActiveSessionFailure(
            isSessionConfigured: false, alreadyReported: true))
    }

    /// With the session up, the failure came from the engine, which reports itself.
    func test_activeSessionFailure_ignoresEngineFailures() {
        XCTAssertFalse(AudioManager.shouldReportActiveSessionFailure(
            isSessionConfigured: true, alreadyReported: false))
    }

    // MARK: - 3a. Lag after suspend/resume

    func test_isSuspensionGap_FT8_wholeSlotLate() {
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 15.5, isFT4: false))
    }

    func test_isSuspensionGap_FT8_shortLagIsARealStall() {
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 3.0, isFT4: false))
    }

    func test_isSuspensionGap_FT4_usesTheShorterSlot() {
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 8.0, isFT4: true))
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 8.0, isFT4: false))
    }

    /// A slot that started a whole period ago (resume after suspension) and
    /// one that is a few seconds late (a real stall) are both skipped. Only
    /// the log level differs, which `isSuspensionGap` decides.
    @MainActor
    func test_determineAction_skipsLateSlots() {
        let viewModel = FT8ViewModel(audioManager: MockAudioManager(), engine: MockMessageDecoder())

        for lag in [3.0, 15.5] {
            let slot = SlotInfo(startTime: AppClock.now().addingTimeInterval(-lag),
                                slotIndex: 10, isEven: true, isFT4: false)
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
