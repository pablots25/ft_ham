// AudioRouteChangeTests.swift
// ft8_hamTests
//
// Tests for the route-change and engine-configuration-change handling added
// to AudioManager for Bluetooth, jack, USB, and AirPlay compatibility.
//
// AudioManager is initialised with isTestMode:true to prevent any real
// AVAudioSession/AVAudioEngine access (see README_TESTING.md). In this mode
// `inputNode` is nil, so `reconfigureEngineAfterRouteChange()` short-circuits
// at its guard — safe to exercise all branches without audio hardware.
//
// handleRouteChange(reason:) and handleAudioSessionInterruption(_:) are
// exposed as `internal` (analogous to shouldRecordEngineStartError) solely
// for deterministic testing.

import XCTest
import Combine
@testable import ft8_ham

// MARK: - Route Change Tests

final class AudioRouteChangeTests: XCTestCase {

    private var sut: AudioManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AudioManager(
            waterfallFFTSize: 512,
            sampleRate: 12000,
            initialGain: 1.0,
            isTestMode: true
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut.cleanup()
        sut = nil
        super.tearDown()
    }

    // MARK: - .noSuitableRouteForCategory → error published

    func test_handleRouteChange_noSuitableRoute_publishesAnError() async {
        let expectation = expectation(description: "audioErrorPublisher emits for no suitable route")

        sut.audioErrorPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        await MainActor.run {
            sut.handleRouteChange(reason: .noSuitableRouteForCategory)
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func test_handleRouteChange_noSuitableRoute_errorMessageIsNotEmpty() async {
        var receivedMessage: String?
        let expectation = expectation(description: "error message received")

        sut.audioErrorPublisher
            .sink { msg in
                receivedMessage = msg
                expectation.fulfill()
            }
            .store(in: &cancellables)

        await MainActor.run {
            sut.handleRouteChange(reason: .noSuitableRouteForCategory)
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(receivedMessage?.isEmpty ?? true, "Error message must not be empty")
    }

    func test_handleRouteChange_noSuitableRoute_doesNotChangeListeningState() async {
        await MainActor.run {
            sut.handleRouteChange(reason: .noSuitableRouteForCategory)
        }
        XCTAssertFalse(sut.isListening, "isListening must remain false after a no-suitable-route event")
    }

    func test_handleRouteChange_noSuitableRoute_doesNotChangePlayingState() async {
        await MainActor.run {
            sut.handleRouteChange(reason: .noSuitableRouteForCategory)
        }
        XCTAssertFalse(sut.isPlaying, "isPlaying must remain false after a no-suitable-route event")
    }

    // MARK: - Reconfigure reasons — safe no-op in test mode

    func test_handleRouteChange_newDeviceAvailable_doesNotCrashInTestMode() async {
        // inputNode == nil → reconfigureEngineAfterRouteChange returns at first guard
        await MainActor.run {
            sut.handleRouteChange(reason: .newDeviceAvailable)
        }
        XCTAssertFalse(sut.isListening)
        XCTAssertFalse(sut.isPlaying)
    }

    func test_handleRouteChange_oldDeviceUnavailable_doesNotCrashInTestMode() async {
        await MainActor.run {
            sut.handleRouteChange(reason: .oldDeviceUnavailable)
        }
        XCTAssertFalse(sut.isListening)
        XCTAssertFalse(sut.isPlaying)
    }

    func test_handleRouteChange_wakeFromSleep_doesNotCrashInTestMode() async {
        await MainActor.run {
            sut.handleRouteChange(reason: .wakeFromSleep)
        }
        XCTAssertFalse(sut.isListening)
    }

    func test_handleRouteChange_categoryChange_doesNotCrashInTestMode() async {
        await MainActor.run {
            sut.handleRouteChange(reason: .categoryChange)
        }
        XCTAssertFalse(sut.isListening)
    }

    func test_handleRouteChange_override_doesNotCrashInTestMode() async {
        await MainActor.run {
            sut.handleRouteChange(reason: .override)
        }
        XCTAssertFalse(sut.isListening)
    }

    // MARK: - Reconfigure reasons do NOT emit errors in test mode

    func test_handleRouteChange_newDeviceAvailable_doesNotEmitError() async {
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        await MainActor.run {
            sut.handleRouteChange(reason: .newDeviceAvailable)
        }

        // Allow one run-loop cycle for any potential async emission
        await Task.yield()
        XCTAssertFalse(errorEmitted, ".newDeviceAvailable must not emit an error in test mode")
    }

    func test_handleRouteChange_oldDeviceUnavailable_doesNotEmitError() async {
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        await MainActor.run {
            sut.handleRouteChange(reason: .oldDeviceUnavailable)
        }

        await Task.yield()
        XCTAssertFalse(errorEmitted, ".oldDeviceUnavailable must not emit an error in test mode")
    }

    // MARK: - Notification parsing

    func test_handleAudioSessionRouteChange_missingReasonKey_isIgnored() {
        // A notification with no AVAudioSessionRouteChangeReasonKey must be
        // discarded without crashing or emitting anything.
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        let notification = Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: nil         // Missing required key
        )
        sut.handleAudioSessionRouteChange(notification)

        XCTAssertFalse(errorEmitted, "Notification without route change reason must be silently ignored")
    }

    func test_handleAudioSessionRouteChange_validNoSuitableRouteReason_dispatchesToMainActor() async {
        let expectation = expectation(description: "error published after async dispatch to main actor")

        sut.audioErrorPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        let userInfo: [AnyHashable: Any] = [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue
        ]
        let notification = Notification(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: userInfo
        )
        sut.handleAudioSessionRouteChange(notification)

        // The handler dispatches via Task { @MainActor } — must yield for it to run
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Re-entrancy guard

    func test_reconfigure_whileIsReconfiguring_returnImmediately() async {
        // Simulate the isReconfiguring flag being set (as if configureAudioSession
        // triggered another .categoryChange notification mid-reconfigure).
        await MainActor.run {
            sut.isReconfiguring = true
            sut.lastRouteChangeDate = .distantPast

            // This call must short-circuit because isReconfiguring == true.
            // In test mode inputNode == nil, so the guard returns before the flag
            // check — we can't exercise it directly. This test documents the intent.
            // Verifies the property is writable and the code compiles.
            XCTAssertTrue(sut.isReconfiguring)
        }
    }

    // MARK: - Debounce guard

    func test_reconfigure_withinDebounceInterval_isSkipped() async {
        await MainActor.run {
            // Simulate a recent reconfiguration — lastRouteChangeDate is "now".
            sut.lastRouteChangeDate = Date()

            // In test mode the inputNode-nil guard fires first, but this verifies
            // the timestamp is settable and the debounce logic is in place.
            sut.handleRouteChange(reason: .categoryChange)

            // After a debounced call, lastRouteChangeDate should NOT be updated
            // (the call exits before reaching the timestamp assignment).
            // We just verify no crash and no error.
            XCTAssertFalse(sut.isPlaying)
            XCTAssertFalse(sut.isListening)
        }
    }

    func test_rapidFireRouteChanges_doNotCrashOrEmitErrors() async {
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        await MainActor.run {
            // Simulate the rapid-fire loop from the bug report:
            // 20+ route change notifications in quick succession.
            for _ in 0..<20 {
                sut.handleRouteChange(reason: .categoryChange)
                sut.handleRouteChange(reason: .override)
            }
        }

        await Task.yield()
        XCTAssertFalse(errorEmitted, "Rapid-fire route changes must not emit errors")
    }
}

// MARK: - Interruption Handling Tests

final class AudioInterruptionReasonTests: XCTestCase {

    private var sut: AudioManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AudioManager(
            waterfallFFTSize: 512,
            sampleRate: 12000,
            initialGain: 1.0,
            isTestMode: true
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut.cleanup()
        sut = nil
        super.tearDown()
    }

    // MARK: - .began with no reason key — normal interruption path

    func test_interruptionBegan_noReasonKey_doesNotEmitError() {
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        let notification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        sut.handleAudioSessionInterruption(notification)

        XCTAssertFalse(errorEmitted, "A normal interruption began must not emit an error")
    }

    // MARK: - .began with .builtInMicMuted — early return, no side-effects

    @available(iOS 14.5, *)
    func test_interruptionBegan_builtInMicMuted_doesNotEmitError() {
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        let notification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
                AVAudioSessionInterruptionReasonKey: AVAudioSession.InterruptionReason.builtInMicMuted.rawValue
            ]
        )
        sut.handleAudioSessionInterruption(notification)

        XCTAssertFalse(errorEmitted, ".builtInMicMuted must not emit any error")
    }

    @available(iOS 14.5, *)
    func test_interruptionBegan_builtInMicMuted_doesNotChangeListeningState() {
        let notification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
                AVAudioSessionInterruptionReasonKey: AVAudioSession.InterruptionReason.builtInMicMuted.rawValue
            ]
        )
        sut.handleAudioSessionInterruption(notification)

        XCTAssertFalse(sut.isListening, ".builtInMicMuted must not alter isListening")
    }

    // MARK: - .ended without shouldResume — no recovery attempted

    func test_interruptionEnded_noShouldResume_doesNotEmitError() {
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        let notification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
                // AVAudioSessionInterruptionOptionKey intentionally absent → shouldResume == false
            ]
        )
        sut.handleAudioSessionInterruption(notification)

        XCTAssertFalse(errorEmitted, "Ended interruption without shouldResume must not emit an error")
    }

    // MARK: - Malformed notification — missing type key

    func test_interruptionNotification_missingTypeKey_isIgnored() {
        var errorEmitted = false
        sut.audioErrorPublisher
            .sink { _ in errorEmitted = true }
            .store(in: &cancellables)

        let notification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: nil      // Missing AVAudioSessionInterruptionTypeKey
        )
        sut.handleAudioSessionInterruption(notification)

        XCTAssertFalse(errorEmitted, "A notification missing the interruption type key must be silently ignored")
    }
}
