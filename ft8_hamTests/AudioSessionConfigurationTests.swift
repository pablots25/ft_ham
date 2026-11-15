// AudioSessionConfigurationTests.swift
// ft8_hamTests
//
// Regression tests for the 1.3.1 hang in AudioManager.configureAudioSession():
// a route change (Bluetooth connect/disconnect, wake from sleep) re-issued
// AVAudioSession.setCategory on the main thread every time, and the media
// server blocked that call for over 3 seconds. The session is now only
// reconfigured when its category, options, mode or sample rate actually differ.
// These tests cover the pure decision helpers. They never touch the real session.

import XCTest
import AVFoundation
@testable import ft8_ham

final class AudioSessionConfigurationTests: XCTestCase {

    // MARK: - Category

    func test_categoryUpdate_notNeededWhenCategoryAndOptionsMatch() {
        XCTAssertFalse(AudioManager.sessionCategoryNeedsUpdate(
            category: AudioManager.sessionCategory,
            options: AudioManager.sessionCategoryOptions
        ))
    }

    func test_categoryUpdate_notNeededWhenTheSystemAddedExtraOptions() {
        // iOS can report extra options (e.g. mixWithOthers set by the system
        // when the route changes). Ours are still present, so nothing to do.
        let options = AudioManager.sessionCategoryOptions.union(.mixWithOthers)
        XCTAssertFalse(AudioManager.sessionCategoryNeedsUpdate(
            category: AudioManager.sessionCategory,
            options: options
        ))
    }

    func test_categoryUpdate_neededWhenCategoryDiffers() {
        XCTAssertTrue(AudioManager.sessionCategoryNeedsUpdate(
            category: .soloAmbient,
            options: AudioManager.sessionCategoryOptions
        ))
    }

    func test_categoryUpdate_neededWhenAnOptionIsMissing() {
        var options = AudioManager.sessionCategoryOptions
        options.remove(.allowBluetoothHFP)
        XCTAssertTrue(AudioManager.sessionCategoryNeedsUpdate(
            category: AudioManager.sessionCategory,
            options: options
        ))
    }

    func test_categoryUpdate_neededOnAFreshSession() {
        // A brand-new session reports .soloAmbient with no options.
        XCTAssertTrue(AudioManager.sessionCategoryNeedsUpdate(category: .soloAmbient, options: []))
    }

    // MARK: - Mode

    func test_modeUpdate_notNeededWhenModeMatches() {
        XCTAssertFalse(AudioManager.sessionModeNeedsUpdate(mode: AudioManager.sessionMode))
    }

    func test_modeUpdate_neededWhenModeDiffers() {
        XCTAssertTrue(AudioManager.sessionModeNeedsUpdate(mode: .default))
    }

    // MARK: - Sample rate

    func test_sampleRateUpdate_notNeededWhenPreferredRateMatches() {
        XCTAssertFalse(AudioManager.sessionSampleRateNeedsUpdate(
            preferredSampleRate: AudioManager.preferredSessionSampleRate
        ))
    }

    func test_sampleRateUpdate_neededWhenNoPreferenceIsSet() {
        // AVAudioSession reports 0 until a preferred rate is set.
        XCTAssertTrue(AudioManager.sessionSampleRateNeedsUpdate(preferredSampleRate: 0))
    }

    func test_sampleRateUpdate_neededWhenPreferredRateDiffers() {
        XCTAssertTrue(AudioManager.sessionSampleRateNeedsUpdate(preferredSampleRate: 48000))
    }

    // MARK: - Configuration values

    func test_sessionConfiguration_keepsThe131Values() {
        XCTAssertEqual(AudioManager.sessionCategory, .playAndRecord)
        XCTAssertEqual(AudioManager.sessionMode, .measurement)
        XCTAssertEqual(AudioManager.preferredSessionSampleRate, 44100)
        XCTAssertEqual(
            AudioManager.sessionCategoryOptions,
            [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
        )
    }
}
