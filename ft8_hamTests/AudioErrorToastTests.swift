//
//  AudioErrorToastTests.swift
//  ft8_hamTests
//
//  Audio engine errors used to be published with no subscriber. They now show
//  as a warning toast, throttled so a repeating error does not flood the UI.
//

import XCTest
@testable import ft8_ham

// MARK: - RepeatThrottle

final class RepeatThrottleTests: XCTestCase {

    func test_sameMessageBlockedWithinInterval() {
        var throttle = RepeatThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(throttle.shouldShow("Engine failed", at: t0))
        XCTAssertFalse(throttle.shouldShow("Engine failed", at: t0.addingTimeInterval(9.9)))
        XCTAssertTrue(throttle.shouldShow("Engine failed", at: t0.addingTimeInterval(10)))
    }

    func test_differentMessagesAreIndependent() {
        var throttle = RepeatThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(throttle.shouldShow("A", at: t0))
        XCTAssertTrue(throttle.shouldShow("B", at: t0.addingTimeInterval(1)))
    }
}

// MARK: - View model

@MainActor
final class AudioErrorToastTests: XCTestCase {

    private var audio: MockAudioManager!
    private var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        audio = MockAudioManager()
        viewModel = FT8ViewModel(audioManager: audio, engine: MockMessageDecoder())
        viewModel.toast = nil
    }

    override func tearDown() async throws {
        viewModel = nil
        audio = nil
        try await super.tearDown()
    }

    /// Lets the main-actor hop from the publisher sink run.
    private func drainMainActor() async {
        for _ in 0..<5 { await Task.yield() }
    }

    func test_publishedAudioError_showsWarningToast() async {
        audio.simulateError("No audio output available.")
        await drainMainActor()

        XCTAssertEqual(viewModel.audioError, "No audio output available.")
        XCTAssertEqual(viewModel.toast?.message, "No audio output available.")
        XCTAssertEqual(viewModel.toast?.systemImage, ToastMessage.warning("").systemImage)
    }

    func test_sameErrorIsNotRepeatedWithinTenSeconds() async {
        audio.simulateError("Engine failed")
        await drainMainActor()
        XCTAssertNotNil(viewModel.toast)

        viewModel.toast = nil
        audio.simulateError("Engine failed")
        await drainMainActor()
        XCTAssertNil(viewModel.toast)
    }

    func test_differentErrorStillShows() async {
        audio.simulateError("Engine failed")
        await drainMainActor()
        viewModel.toast = nil

        audio.simulateError("Route lost")
        await drainMainActor()
        XCTAssertEqual(viewModel.toast?.message, "Route lost")
    }

    func test_throttleExpiresAfterInterval() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        viewModel.showAudioErrorToast("Engine failed", at: t0)
        viewModel.toast = nil

        viewModel.showAudioErrorToast("Engine failed", at: t0.addingTimeInterval(5))
        XCTAssertNil(viewModel.toast)

        viewModel.showAudioErrorToast("Engine failed", at: t0.addingTimeInterval(11))
        XCTAssertEqual(viewModel.toast?.message, "Engine failed")
    }

    func test_directAudioErrorWriteAlsoShowsToast() {
        viewModel.audioError = "Invalid callsign/locator"
        XCTAssertEqual(viewModel.toast?.message, "Invalid callsign/locator")
    }
}
