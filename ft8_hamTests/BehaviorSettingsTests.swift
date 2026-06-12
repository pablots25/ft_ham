//
//  BehaviorSettingsTests.swift
//  ft8_hamTests
//
//  Created by GitHub Copilot on 04/04/26.
//

import XCTest
@testable import ft8_ham

// MARK: - Behavior Settings Unit Tests

/// Tests that validate BehaviorSettings properties in FT8ViewModel,
/// covering defaults, mutations, and persistence via UserDefaults (@AppStorage).
@MainActor
final class BehaviorSettingsTests: XCTestCase {

    var viewModel: FT8ViewModel!

    // Keys that match the @AppStorage keys in FT8ViewModel
    private let behaviorSettingsKeys = [
        "autoRXAtStart",
        "autoSequencingEnabled",
        "decodeSelfTXMessages",
        "autoCQReplyEnabled",
        "autoCQReplyOnlyNewBandMode",
        "maxRetrySlots",
        "autoQSOLogging",
        "holdTXFrequency",
        "pskReporterEnabled",
    ]

    override func setUp() async throws {
        try await super.setUp()
        // Remove all behavior-setting keys before each test so @AppStorage
        // falls back to the declared defaults rather than leftover state.
        behaviorSettingsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        viewModel = FT8ViewModel(txMessages: [], rxMessages: [])
    }

    override func tearDown() async throws {
        behaviorSettingsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Default Value Tests

    func testAutoRXAtStartDefaultIsFalse() {
        XCTAssertFalse(viewModel.autoRXAtStart, "autoRXAtStart should default to false")
    }

    func testAutoSequencingEnabledDefaultIsTrue() {
        XCTAssertTrue(viewModel.autoSequencingEnabled, "autoSequencingEnabled should default to true")
    }

    func testDecodeSelfTXMessagesDefaultIsFalse() {
        XCTAssertFalse(viewModel.decodeSelfTXMessages, "decodeSelfTXMessages should default to false")
    }

    func testAutoCQReplyEnabledDefaultIsFalse() {
        XCTAssertFalse(viewModel.autoCQReplyEnabled, "autoCQReplyEnabled should default to false")
    }

    func testAutoCQReplyOnlyNewBandModeDefaultIsFalse() {
        XCTAssertFalse(viewModel.autoCQReplyOnlyNewBandMode, "autoCQReplyOnlyNewBandMode should default to false")
    }

    func testMaxRetrySlotsDefaultIsThree() {
        XCTAssertEqual(viewModel.maxRetrySlots, 3, "maxRetrySlots should default to 3")
    }

    func testAutoQSOLoggingDefaultIsTrue() {
        XCTAssertTrue(viewModel.autoQSOLogging, "autoQSOLogging should default to true")
    }

    func testHoldTXFrequencyDefaultIsFalse() {
        XCTAssertFalse(viewModel.holdTXFrequency, "holdTXFrequency should default to false")
    }

    func testPSKReporterEnabledDefaultIsFalse() {
        XCTAssertFalse(viewModel.pskReporterEnabled, "pskReporterEnabled should default to false")
    }

    // MARK: - Mutation Tests

    func testToggleAutoRXAtStart() {
        viewModel.autoRXAtStart = true
        XCTAssertTrue(viewModel.autoRXAtStart)

        viewModel.autoRXAtStart = false
        XCTAssertFalse(viewModel.autoRXAtStart)
    }

    func testToggleAutoSequencingEnabled() {
        viewModel.autoSequencingEnabled = false
        XCTAssertFalse(viewModel.autoSequencingEnabled)

        viewModel.autoSequencingEnabled = true
        XCTAssertTrue(viewModel.autoSequencingEnabled)
    }

    func testToggleDecodeSelfTXMessages() {
        viewModel.decodeSelfTXMessages = true
        XCTAssertTrue(viewModel.decodeSelfTXMessages)

        viewModel.decodeSelfTXMessages = false
        XCTAssertFalse(viewModel.decodeSelfTXMessages)
    }

    func testToggleAutoCQReplyEnabled() {
        viewModel.autoCQReplyEnabled = true
        XCTAssertTrue(viewModel.autoCQReplyEnabled)

        viewModel.autoCQReplyEnabled = false
        XCTAssertFalse(viewModel.autoCQReplyEnabled)
    }

    func testToggleAutoCQReplyOnlyNewBandMode() {
        viewModel.autoCQReplyOnlyNewBandMode = true
        XCTAssertTrue(viewModel.autoCQReplyOnlyNewBandMode)

        viewModel.autoCQReplyOnlyNewBandMode = false
        XCTAssertFalse(viewModel.autoCQReplyOnlyNewBandMode)
    }

    func testToggleAutoQSOLogging() {
        viewModel.autoQSOLogging = false
        XCTAssertFalse(viewModel.autoQSOLogging)

        viewModel.autoQSOLogging = true
        XCTAssertTrue(viewModel.autoQSOLogging)
    }

    func testToggleHoldTXFrequency() {
        viewModel.holdTXFrequency = true
        XCTAssertTrue(viewModel.holdTXFrequency)

        viewModel.holdTXFrequency = false
        XCTAssertFalse(viewModel.holdTXFrequency)
    }

    func testTogglePSKReporterEnabled() {
        viewModel.pskReporterEnabled = true
        XCTAssertTrue(viewModel.pskReporterEnabled)

        viewModel.pskReporterEnabled = false
        XCTAssertFalse(viewModel.pskReporterEnabled)
    }

    // MARK: - maxRetrySlots Boundary Tests

    func testMaxRetrySlotsCanBeSetToOne() {
        viewModel.maxRetrySlots = 1
        XCTAssertEqual(viewModel.maxRetrySlots, 1)
    }

    func testMaxRetrySlotsCanBeSetToTen() {
        viewModel.maxRetrySlots = 10
        XCTAssertEqual(viewModel.maxRetrySlots, 10)
    }

    func testMaxRetrySlotsCanBeUpdatedMultipleTimes() {
        viewModel.maxRetrySlots = 5
        XCTAssertEqual(viewModel.maxRetrySlots, 5)
        viewModel.maxRetrySlots = 2
        XCTAssertEqual(viewModel.maxRetrySlots, 2)
    }

    // MARK: - UserDefaults Persistence Tests

    func testAutoRXAtStartPersistsToUserDefaults() {
        viewModel.autoRXAtStart = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "autoRXAtStart"))
    }

    func testAutoCQReplyEnabledPersistsToUserDefaults() {
        viewModel.autoCQReplyEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "autoCQReplyEnabled"))
    }

    func testAutoSequencingEnabledPersistsToUserDefaults() {
        viewModel.autoSequencingEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "autoSequencingEnabled"))
    }

    func testMaxRetrySlotsPersistsToUserDefaults() {
        viewModel.maxRetrySlots = 7
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "maxRetrySlots"), 7)
    }

    func testAutoQSOLoggingPersistsToUserDefaults() {
        viewModel.autoQSOLogging = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "autoQSOLogging"))
    }

    func testHoldTXFrequencyPersistsToUserDefaults() {
        viewModel.holdTXFrequency = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "holdTXFrequency"))
    }

    // MARK: - Setting Interactions

    func testDisablingAutoCQReplyDoesNotAffectNewBandModeFlag() {
        viewModel.autoCQReplyEnabled = true
        viewModel.autoCQReplyOnlyNewBandMode = true

        viewModel.autoCQReplyEnabled = false

        // The sub-flag should remain unchanged when the parent toggle is disabled
        XCTAssertTrue(viewModel.autoCQReplyOnlyNewBandMode,
                      "autoCQReplyOnlyNewBandMode should be independent of autoCQReplyEnabled")
    }

    func testAutoSequencingAndAutoQSOLoggingAreIndependent() {
        viewModel.autoSequencingEnabled = false
        viewModel.autoQSOLogging = true

        XCTAssertFalse(viewModel.autoSequencingEnabled)
        XCTAssertTrue(viewModel.autoQSOLogging)
    }
}
