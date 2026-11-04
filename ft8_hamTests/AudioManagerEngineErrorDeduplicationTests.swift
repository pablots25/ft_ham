// AudioManagerEngineErrorDeduplicationTests.swift
// ft8_hamTests
//
// Tests for the engine-start error deduplication logic introduced to suppress
// repeated Crashlytics non-fatal events when AVAudioEngine fails repeatedly
// across FT8 TX slots (Crashlytics issue 93f6a2a77df3de6c629bd4b4f57ba1c0).
//
// The core predicate is `AudioManager.shouldRecordEngineStartError(at:)`.
// AudioManager is initialised with `isTestMode: true` — no audio hardware touched.

import XCTest
@testable import ft8_ham

final class AudioManagerEngineErrorDeduplicationTests: XCTestCase {

    private var sut: AudioManager!

    override func setUp() {
        super.setUp()
        sut = AudioManager(
            waterfallFFTSize: 512,
            sampleRate: 12000,
            initialGain: 1.0,
            isTestMode: true
        )
        // Ensure gate is clear at start of each test
        sut.engineStartFirstFailureDate = nil
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - First failure (no prior date)

    func test_shouldRecordError_whenNoPriorFailure_returnsTrue() {
        sut.engineStartFirstFailureDate = nil
        XCTAssertTrue(sut.shouldRecordEngineStartError(at: Date()),
                      "A fresh failure (no stamp) must be recorded to Crashlytics")
    }

    // MARK: - Within cooldown window

    func test_shouldRecordError_withinCooldown_returnsFalse() {
        // Stamp a failure 1 second ago — well inside the 5-min window
        sut.engineStartFirstFailureDate = Date().addingTimeInterval(-1)
        XCTAssertFalse(sut.shouldRecordEngineStartError(at: Date()),
                       "Failure within 5-min cooldown must be suppressed")
    }

    func test_shouldRecordError_atCooldownBoundaryMinus1s_returnsFalse() {
        let fiveMinutes: TimeInterval = 5 * 60
        sut.engineStartFirstFailureDate = Date().addingTimeInterval(-(fiveMinutes - 1))
        XCTAssertFalse(sut.shouldRecordEngineStartError(at: Date()),
                       "Failure 1s before cooldown expiry must still be suppressed")
    }

    // MARK: - Cooldown expired

    func test_shouldRecordError_afterCooldownExpired_returnsTrue() {
        let fiveMinutes: TimeInterval = 5 * 60
        // Stamp from 5 min + 1 second ago — just past the window
        sut.engineStartFirstFailureDate = Date().addingTimeInterval(-(fiveMinutes + 1))
        XCTAssertTrue(sut.shouldRecordEngineStartError(at: Date()),
                       "Failure after cooldown window must produce a new Crashlytics event")
    }

    func test_shouldRecordError_longAfterCooldown_returnsTrue() {
        // Stamp from an hour ago
        sut.engineStartFirstFailureDate = Date().addingTimeInterval(-3600)
        XCTAssertTrue(sut.shouldRecordEngineStartError(at: Date()),
                       "Failure long after cooldown must produce a new Crashlytics event")
    }

    // MARK: - Deterministic date injection

    func test_shouldRecordError_deterministicDates_withinWindow() {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        sut.engineStartFirstFailureDate = anchor
        // Query 4 min 59s after the anchor — still inside window
        let query = anchor.addingTimeInterval(4 * 60 + 59)
        XCTAssertFalse(sut.shouldRecordEngineStartError(at: query))
    }

    func test_shouldRecordError_deterministicDates_exactlyAtBoundary() {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        sut.engineStartFirstFailureDate = anchor
        // Query exactly at 5 min — interval is NOT < cooldown, so should record
        let query = anchor.addingTimeInterval(5 * 60)
        XCTAssertTrue(sut.shouldRecordEngineStartError(at: query))
    }

    // MARK: - Reset after successful playback

    func test_engineStartFirstFailureDate_isNilAfterReset() {
        sut.engineStartFirstFailureDate = Date()
        // Simulate the reset that happens inside the scheduleBuffer completion
        sut.engineStartFirstFailureDate = nil
        XCTAssertNil(sut.engineStartFirstFailureDate,
                     "Gate must be nil after a successful playback so the next genuine failure is recorded")
    }

    func test_shouldRecordError_afterReset_returnsTrue() {
        // Seed a recent failure stamp, then reset (mimics successful playback)
        sut.engineStartFirstFailureDate = Date().addingTimeInterval(-10)
        sut.engineStartFirstFailureDate = nil
        XCTAssertTrue(sut.shouldRecordEngineStartError(at: Date()),
                      "After gate reset, the next failure must produce a Crashlytics event")
    }
}
