//
//  FeatureFlagDefaultsTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 26/10/26.
//

import XCTest
@testable import ft8_ham

/// Features that ship dark must default to off, so a key missing from
/// Remote Config keeps them hidden.
final class FeatureFlagDefaultsTests: XCTestCase {

    func test_heardMeMapLayer_isOffByDefault() {
        XCTAssertFalse(FeatureFlag.enableHeardMe.defaultValue)
    }

    func test_quickConfigSheet_isOffByDefault() {
        XCTAssertFalse(FeatureFlag.controlsSheet.defaultValue)
    }

    /// The new Configuration screen is live for everyone, so it must not depend
    /// on Remote Config being reachable to show up.
    func test_newConfigView_isOnByDefault() {
        XCTAssertTrue(FeatureFlag.newConfigView.defaultValue)
    }

    func test_heardMeFlag_usesItsRemoteConfigKey() {
        XCTAssertEqual(FeatureFlag.enableHeardMe.rawValue, "enableHeardMe")
        XCTAssertEqual(FeatureFlag.controlsSheet.rawValue, "controlsSheet")
    }

    /// The Remote Config key the 1.3.2 rollout uses.
    func test_rxSlotCutFlag_usesItsRemoteConfigKey() {
        XCTAssertEqual(FeatureFlag.rxSlotCutOnAudioTime.rawValue, "rxSlotCutOnAudioTime")
    }

    /// Tests build in debug, where the flag is on for device testing. The
    /// release default (off) is checked by `#if DEBUG` in FeatureFlag.swift.
    func test_rxSlotCutFlag_isOnInDebugBuilds() {
        #if DEBUG
        XCTAssertTrue(FeatureFlag.rxSlotCutOnAudioTime.defaultValue)
        #else
        XCTAssertFalse(FeatureFlag.rxSlotCutOnAudioTime.defaultValue)
        #endif
    }
}
