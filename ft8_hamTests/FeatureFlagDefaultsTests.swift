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

    func test_heardMeFlag_usesItsRemoteConfigKey() {
        XCTAssertEqual(FeatureFlag.enableHeardMe.rawValue, "enableHeardMe")
        XCTAssertEqual(FeatureFlag.controlsSheet.rawValue, "controlsSheet")
    }
}
