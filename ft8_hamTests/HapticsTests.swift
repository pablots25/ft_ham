//
//  HapticsTests.swift
//  ft8_hamTests
//
//  Smoke test for the shared haptic generators: every semantic method can be
//  called repeatedly (the generator is re-prepared after each use) without
//  crashing, including on hardware or simulators without a Taptic Engine.
//

import XCTest
@testable import ft8_ham

@MainActor
final class HapticsTests: XCTestCase {

    func test_allFeedbackKindsCanFireRepeatedly() {
        Haptics.prepare()
        for _ in 0..<3 {
            Haptics.light()
            Haptics.medium()
            Haptics.success()
            Haptics.warning()
            Haptics.error()
            Haptics.selection()
        }
    }
}
