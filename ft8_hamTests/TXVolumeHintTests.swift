// TXVolumeHintTests.swift
// ft8_hamTests
//
// Tests for the rule that shows the "turn the device volume up" hint under
// the TX output gain slider. Pure logic, no AVAudioSession access.

import XCTest
@testable import ft8_ham

final class TXVolumeHintTests: XCTestCase {

    func test_fullVolume_hidesHint() {
        XCTAssertFalse(TXVolumeHint.shouldShow(forVolume: 1.0))
    }

    func test_volumeAtThreshold_hidesHint() {
        XCTAssertFalse(TXVolumeHint.shouldShow(forVolume: TXVolumeHint.fullVolumeThreshold))
    }

    func test_oneButtonStepBelowMaximum_showsHint() {
        // The volume buttons move outputVolume in 1/16 steps.
        XCTAssertTrue(TXVolumeHint.shouldShow(forVolume: 15.0 / 16.0))
    }

    func test_halfVolume_showsHint() {
        XCTAssertTrue(TXVolumeHint.shouldShow(forVolume: 0.5))
    }

    func test_muted_showsHint() {
        XCTAssertTrue(TXVolumeHint.shouldShow(forVolume: 0))
    }

    func test_nonFiniteVolume_hidesHint() {
        XCTAssertFalse(TXVolumeHint.shouldShow(forVolume: .nan))
        XCTAssertFalse(TXVolumeHint.shouldShow(forVolume: .infinity))
    }
}
