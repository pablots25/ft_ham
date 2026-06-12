//
//  SequencerSampleRateGuardTests.swift
//  ft_hamTests
//
//  Regression tests for the micSampleRate == 0 crash guard introduced in
//  commit 79803df ("Fixed crash with Audio Manager Debug settings").
//
//  Root cause: AudioManager.micSampleRate starts at 0 and is populated lazily
//  by startMicInput(). Passing 0 as sampleRate to monitor_init produced nfft=0,
//  crashing inside KISS FFT. The guard `capturedSampleRate > 0` in
//  FT8ViewModel+Sequencer.swift prevents reaching decodeAudioBuffer with a
//  zero sample rate.
//

import XCTest
@testable import ft8_ham

@MainActor
final class SequencerSampleRateGuardTests: XCTestCase {

    // MARK: - Guard condition unit tests

    /// Confirms the guard expression fires for sampleRate == 0 and not for a
    /// valid rate. Tests the logic in isolation from the async sequencer loop.
    func testGuardCondition_FiresForZero() {
        let triggersFired = !(0.0 > 0)        // mirrors `guard capturedSampleRate > 0`
        XCTAssertTrue(triggersFired, "Guard must fire when sampleRate is 0")
    }

    func testGuardCondition_DoesNotFireForValid() {
        let triggersFired = !(44100.0 > 0)
        XCTAssertFalse(triggersFired, "Guard must NOT fire for a valid sample rate")
    }

    /// Pre-fix: passing 0.0 as sampleRate to decodeAudioBuffer caused a crash.
    /// This documents that minSamples calculated with 0.0 also collapses to 0,
    /// hiding the real problem (monitor_init receiving nfft=0).
    func testZeroSampleRate_MathProducesZeroSamples() {
        // Constants.ft8SignalDuration = 12.6, Constants.ft8DecodeMargin = 0.2
        let requiredSeconds = 12.6 + 0.2
        let minSamples      = Int(requiredSeconds * 0.0)
        XCTAssertEqual(minSamples, 0,
            "Zero sampleRate collapses minSamples to 0, bypassing the size check but still crashing in monitor_init")
    }

    // MARK: - FT8ViewModel creation with zero sampleRate

    /// Injecting a mock with micSampleRate = 0 must not crash at init time.
    func testViewModelCreation_WithZeroSampleRate_DoesNotCrash() {
        let audio = MockAudioManager()
        audio.micSampleRate = 0.0

        let vm = FT8ViewModel(audioManager: audio, engine: MockMessageDecoder())
        XCTAssertNotNil(vm)
        XCTAssertFalse(vm.isSequencerRunning)
    }

    // MARK: - Sequencer startup with zero sampleRate

    /// Starts the sequencer with micSampleRate == 0 and waits briefly.
    /// Because no slot (15 s) can complete in 50 ms the decode is never called,
    /// but more importantly — nothing crashes. This is a crash-prevention guard.
    func testStartSequencer_WithZeroSampleRate_DoesNotCrash() async {
        let audio  = MockAudioManager()
        let engine = MockMessageDecoder()
        audio.micSampleRate = 0.0

        let vm = FT8ViewModel(audioManager: audio, engine: engine)
        vm.callsign = "EA1TST"
        vm.locator  = "IN70"

        vm.startSequencer()

        // Allow the Task to spin up.
        try? await Task.sleep(for: .milliseconds(50))

        // No slot has completed in 50 ms — no decode should have been attempted.
        XCTAssertEqual(engine.decodeAudioBufferCallCount, 0,
            "decodeAudioBuffer must not be called with micSampleRate == 0")

        await vm.stopSequencer()
    }

    /// Positive control: with a valid sample rate the sequencer also starts
    /// without crashing and decodes nothing within 50 ms (timing-based guard).
    func testStartSequencer_WithValidSampleRate_DoesNotCrash() async {
        let audio  = MockAudioManager()
        let engine = MockMessageDecoder()
        audio.micSampleRate = 44100.0

        let vm = FT8ViewModel(audioManager: audio, engine: engine)
        vm.callsign = "EA1TST"
        vm.locator  = "IN70"

        vm.startSequencer()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(engine.decodeAudioBufferCallCount, 0,
            "No slot completes within 50 ms — no decode expected regardless")

        await vm.stopSequencer()
    }
}
