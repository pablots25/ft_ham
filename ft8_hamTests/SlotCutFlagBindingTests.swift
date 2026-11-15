//
//  SlotCutFlagBindingTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 12/11/26.
//

import XCTest
@testable import ft8_ham

/// The `rxSlotCutOnAudioTime` flag drives the slot monitor's kill switch,
/// at bind time and whenever the flag changes.
@MainActor
final class SlotCutFlagBindingTests: XCTestCase {

    private let flag = FeatureFlag.rxSlotCutOnAudioTime
    private var overrideKey: String { "debug.\(flag.rawValue)Override" }
    private var savedOverride: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedOverride = UserDefaults.standard.object(forKey: overrideKey)
    }

    override func tearDown() async throws {
        #if DEBUG
        if let saved = savedOverride as? Bool {
            FeatureFlagManager.shared.setOverride(flag, value: saved)
        } else {
            FeatureFlagManager.shared.setOverride(flag, value: flag.defaultValue)
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
        #endif
        try await super.tearDown()
    }

    #if DEBUG
    func test_bindingFollowsTheFlag() {
        let vm = FT8ViewModel()
        let flags = FeatureFlagManager.shared

        flags.setOverride(flag, value: false)
        vm.bindSlotCutFlag(flags)
        XCTAssertFalse(vm.slotMonitor.cutsAtSlotBoundary, "applied when bound")

        flags.setOverride(flag, value: true)
        XCTAssertTrue(vm.slotMonitor.cutsAtSlotBoundary, "follows the switch on")

        flags.setOverride(flag, value: false)
        XCTAssertFalse(vm.slotMonitor.cutsAtSlotBoundary, "and off again")
    }
    #endif
}
