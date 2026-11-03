//
//  DigitalModePortTests.swift
//  ft8_hamTests
//

import XCTest
@testable import ft8_ham

/// `DigitalMode` as the single source of per-mode parameters. Pure logic, no
/// audio hardware or network involved.
@MainActor
final class DigitalModePortTests: XCTestCase {

    // MARK: - DigitalMode

    func test_slotDurations() {
        XCTAssertEqual(DigitalMode.ft8.slotDuration, 15.0)
        XCTAssertEqual(DigitalMode.ft4.slotDuration, 7.5)
    }

    func test_minimumDecodeDuration_keepsPreviousConstants() {
        XCTAssertEqual(DigitalMode.ft8.minimumDecodeDuration, 12.8, accuracy: 1e-9)
        XCTAssertEqual(DigitalMode.ft4.minimumDecodeDuration, 4.6, accuracy: 1e-9)
        XCTAssertEqual(DigitalMode.ft8.maxStartOffset, 2.4)
        XCTAssertEqual(DigitalMode.ft4.maxStartOffset, 0.8)
    }

    func test_qsoModes_useTheEngine() {
        XCTAssertTrue(DigitalMode.ft8.supportsQSO)
        XCTAssertTrue(DigitalMode.ft4.supportsQSO)
        XCTAssertEqual(DigitalMode.ft8.engineProtocol, .ft8)
        XCTAssertEqual(DigitalMode.ft4.engineProtocol, .ft4)
    }

    func test_selectableCases_onlyListAvailableModes() {
        XCTAssertTrue(DigitalMode.selectableCases.allSatisfy(\.isAvailable))
        XCTAssertEqual(DigitalMode.selectableCases.prefix(2), [.ft8, .ft4])
    }

    func test_loadStored_migratesLegacyBool() throws {
        let suite = "DigitalModePortTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: DigitalMode.legacyStorageKey)
        XCTAssertEqual(DigitalMode.loadStored(from: defaults), .ft4)
        XCTAssertEqual(defaults.string(forKey: DigitalMode.storageKey), "ft4")

        defaults.set("ft8", forKey: DigitalMode.storageKey)
        XCTAssertEqual(DigitalMode.loadStored(from: defaults), .ft8)
    }

    func test_loadStored_defaultsToFT8() throws {
        let suite = "DigitalModePortTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(DigitalMode.loadStored(from: defaults), .ft8)
    }

    func test_pskReporterMode() {
        XCTAssertEqual(DigitalMode.ft8.pskReporterMode, .ft8)
        XCTAssertEqual(DigitalMode.ft4.pskReporterMode, .ft4)
    }

    func test_adif() {
        XCTAssertEqual(DigitalMode.ft8.adif.mode, "FT8")
        XCTAssertNil(DigitalMode.ft8.adif.submode)
        XCTAssertEqual(DigitalMode.ft4.adif.mode, "MFSK")
        XCTAssertEqual(DigitalMode.ft4.adif.submode, "FT4")
    }

    // MARK: - Slot parity

    /// Odd FT4 slots start on a half second; whole-second rounding used to
    /// label them even, which picked the wrong cycle to answer in.
    func test_calculateCycle_ft4OddSlotsOnHalfSeconds() {
        let minute = Date(timeIntervalSince1970: 1_800_000_000) // :00 UTC
        XCTAssertEqual(FT8Message.calculateCycle(from: minute, mode: .ft4), .even)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(7.6), mode: .ft4), .odd)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(22.6), mode: .ft4), .odd)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(15.1), mode: .ft4), .even)
    }

    func test_calculateCycle_ft8Unchanged() {
        let minute = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(14.9), mode: .ft8), .even)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(15.0), mode: .ft8), .odd)
    }

    // MARK: - Timing helpers

    func test_isSuspensionGap_usesSlotLength() {
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 7.5, mode: .ft4))
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 7.4, mode: .ft4))
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 14.9, mode: .ft8))
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 15, mode: .ft8))
    }

    func test_progressCycleLength_followsMode() {
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.ft8), 15)
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.ft4), 7.5)
    }

    func test_cycleLabels() {
        XCTAssertEqual(RadioSettingsContent.cycleLabels(for: .ft8).odd, "15/45")
        XCTAssertEqual(RadioSettingsContent.cycleLabels(for: .ft4).odd, "7.5")
    }

    // MARK: - Waterfall

    func test_occupiedBandwidth_perMode() {
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .ft8), 50.0)
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .ft4), 83.3)
    }

    func test_txFrequencyRange_keepsSignalInsideDecoderBand() {
        let range = WaterfallViewModel.txFrequencyRange(mode: .ft4)
        XCTAssertEqual(range.lowerBound, 200)
        XCTAssertEqual(range.upperBound + WaterfallViewModel.occupiedBandwidthHz(mode: .ft4), 3000, accuracy: 1e-9)
    }

    func test_slotMonitorProtocol() {
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .ft8), .ft8)
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .ft4), .ft4)
    }

    // MARK: - Dial frequencies

    func test_dialFrequencies() {
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .ft8), 14_074_000)
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .ft4), 14_080_000)
    }
}
