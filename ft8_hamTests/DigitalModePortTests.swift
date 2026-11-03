//
//  DigitalModePortTests.swift
//  ft8_hamTests
//

import XCTest
@testable import ft8_ham

/// `DigitalMode` as the single source of per-mode parameters, and FT2 wired
/// into the streaming decoder. Pure logic and DSP, no audio hardware or
/// network involved.
@MainActor
final class DigitalModePortTests: XCTestCase {

    // MARK: - DigitalMode

    func test_slotDurations() {
        XCTAssertEqual(DigitalMode.ft8.slotDuration, 15.0)
        XCTAssertEqual(DigitalMode.ft4.slotDuration, 7.5)
        XCTAssertEqual(DigitalMode.ft2.slotDuration, 3.75)
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
        XCTAssertTrue(DigitalMode.ft2.supportsQSO)
        XCTAssertEqual(DigitalMode.ft2.engineProtocol, .ft2)
    }

    func test_selectableCases_onlyListAvailableModes() {
        XCTAssertTrue(DigitalMode.selectableCases.allSatisfy(\.isAvailable))
        XCTAssertEqual(DigitalMode.selectableCases.prefix(3), [.ft8, .ft4, .ft2])
    }

    func test_loadStored_migratesLegacyBool() throws {
        let suite = "DigitalModePortTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: DigitalMode.legacyStorageKey)
        XCTAssertEqual(DigitalMode.loadStored(from: defaults), .ft4)
        XCTAssertEqual(defaults.string(forKey: DigitalMode.storageKey), "ft4")

        defaults.set("ft2", forKey: DigitalMode.storageKey)
        XCTAssertEqual(DigitalMode.loadStored(from: defaults), .ft2)
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
        XCTAssertEqual(DigitalMode.ft2.pskReporterMode, .ft2)
    }

    func test_adif() {
        XCTAssertEqual(DigitalMode.ft8.adif.mode, "FT8")
        XCTAssertNil(DigitalMode.ft8.adif.submode)
        XCTAssertEqual(DigitalMode.ft4.adif.mode, "MFSK")
        XCTAssertEqual(DigitalMode.ft4.adif.submode, "FT4")
        XCTAssertEqual(DigitalMode.ft2.adif.mode, "MFSK")
        XCTAssertEqual(DigitalMode.ft2.adif.submode, "FT2")
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

    func test_calculateCycle_ft2() {
        let minute = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(1.0), mode: .ft2), .even)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(3.8), mode: .ft2), .odd)
        XCTAssertEqual(FT8Message.calculateCycle(from: minute.addingTimeInterval(7.6), mode: .ft2), .even)
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
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 3.75, mode: .ft2))
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 3.7, mode: .ft2))
    }

    func test_progressCycleLength_followsMode() {
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.ft8), 15)
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.ft4), 7.5)
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.ft2), 3.75)
    }

    func test_cycleLabels() {
        XCTAssertEqual(RadioSettingsContent.cycleLabels(for: .ft8).odd, "15/45")
        XCTAssertEqual(RadioSettingsContent.cycleLabels(for: .ft4).odd, "7.5")
        XCTAssertEqual(RadioSettingsContent.cycleLabels(for: .ft2).odd, "3.75")
    }

    // MARK: - Waterfall

    func test_occupiedBandwidth_perMode() {
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .ft8), 50.0)
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .ft4), 83.3)
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .ft2), 166.7)
    }

    func test_txFrequencyRange_keepsFT2SignalInsideDecoderBand() {
        let range = WaterfallViewModel.txFrequencyRange(mode: .ft2)
        XCTAssertEqual(range.lowerBound, 200)
        XCTAssertEqual(range.upperBound + WaterfallViewModel.occupiedBandwidthHz(mode: .ft2), 3000, accuracy: 1e-9)
    }

    func test_slotMonitorProtocol() {
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .ft8), .ft8)
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .ft4), .ft4)
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .ft2), .ft2)
    }

    // MARK: - Dial frequencies

    func test_dialFrequencies() {
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .ft8), 14_074_000)
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .ft4), 14_080_000)
        XCTAssertEqual(FT8Message.Band.band40m.frequency(for: .ft2), 7_062_000)
        XCTAssertNil(FT8Message.Band.band2m.frequency(for: .ft2))
    }

    // MARK: - FT2 through the streaming decoder

    /// FT2 streamed through the slot monitor decodes from its snapshot, the
    /// path the sequencer uses.
    func test_ft2_streamedSlotDecodes() {
        let engine = ft8_Engine()
        let message = "CQ EA4TST IN80"
        guard let audio = engine.generateAudio(message, frequency: 1400, mode: .ft2, toFile: nil) else {
            return XCTFail("No audio generated")
        }
        let samples = audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        // 3.75 s slot at 12 kHz.
        XCTAssertEqual(samples.count, 45_000, accuracy: 300)

        let monitor = FT8SlotMonitor(sampleRate: 12_000, mode: .ft2)
        var pos = 0
        while pos < samples.count {
            let n = min(557, samples.count - pos)
            samples[pos ..< pos + n].withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
            pos += n
        }
        let snapshot = monitor.snapshotAndReset()
        XCTAssertGreaterThan(snapshot.duration, DigitalMode.ft2.signalDuration)

        let texts = engine.decodeWaterfallSnapshot(snapshot, mode: .ft2)
            .compactMap { $0["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(texts.contains(message), "'\(message)' decoded as \(texts)")
    }
}
