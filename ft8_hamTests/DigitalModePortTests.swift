//
//  DigitalModePortTests.swift
//  ft8_hamTests
//

import XCTest
@testable import ft8_ham

/// `DigitalMode` as the single source of per-mode parameters, and WSPR wired
/// into the slot pipeline. Pure logic and DSP, no audio hardware or network
/// involved.
@MainActor
final class DigitalModePortTests: XCTestCase {

    // MARK: - DigitalMode

    func test_slotDurations() {
        XCTAssertEqual(DigitalMode.ft8.slotDuration, 15.0)
        XCTAssertEqual(DigitalMode.ft4.slotDuration, 7.5)
        XCTAssertEqual(DigitalMode.wspr.slotDuration, 120.0)
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

    func test_onlyWSPRIsABeaconMode() {
        XCTAssertFalse(DigitalMode.wspr.supportsQSO)
        XCTAssertNil(DigitalMode.wspr.engineProtocol)
    }

    func test_selectableCases_onlyListAvailableModes() {
        XCTAssertTrue(DigitalMode.selectableCases.allSatisfy(\.isAvailable))
        XCTAssertEqual(DigitalMode.selectableCases.prefix(2), [.ft8, .ft4])
        XCTAssertEqual(DigitalMode.selectableCases.contains(.wspr), WSPRSupport.isAvailable)
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

    func test_pskReporterMode_skipsWSPR() {
        XCTAssertEqual(DigitalMode.ft8.pskReporterMode, .ft8)
        XCTAssertEqual(DigitalMode.ft4.pskReporterMode, .ft4)
        XCTAssertNil(DigitalMode.wspr.pskReporterMode)
    }

    func test_adif() {
        XCTAssertEqual(DigitalMode.ft8.adif.mode, "FT8")
        XCTAssertNil(DigitalMode.ft8.adif.submode)
        XCTAssertEqual(DigitalMode.ft4.adif.mode, "MFSK")
        XCTAssertEqual(DigitalMode.ft4.adif.submode, "FT4")
        XCTAssertEqual(DigitalMode.wspr.adif.mode, "WSPR")
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
        XCTAssertFalse(FT8ViewModel.isSuspensionGap(lag: 60, mode: .wspr))
        XCTAssertTrue(FT8ViewModel.isSuspensionGap(lag: 120, mode: .wspr))
    }

    func test_progressCycleLength_followsMode() {
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.ft8), 15)
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.ft4), 7.5)
        XCTAssertEqual(ProgressViewModel.cycleLengthForMode(.wspr), 120)
    }

    /// WSPR slots start on even minutes, which epoch-aligned 120 s slots give.
    func test_progressPhase_wsprAlignsToEvenMinutes() {
        let evenMinute = Date(timeIntervalSince1970: 1_800_000_000) // divisible by 120
        XCTAssertEqual(ProgressViewModel.phase(at: evenMinute, cycleLength: 120), 0, accuracy: 1e-9)
        XCTAssertEqual(ProgressViewModel.phase(at: evenMinute.addingTimeInterval(60), cycleLength: 120), 0.5, accuracy: 1e-9)
    }

    func test_cycleLabels() {
        XCTAssertEqual(RadioSettingsContent.cycleLabels(for: .ft8).odd, "15/45")
        XCTAssertEqual(RadioSettingsContent.cycleLabels(for: .ft4).odd, "7.5")
    }

    func test_wsprPowerLabel() {
        XCTAssertEqual(RadioSettingsContent.wsprPowerLabel(37), "37 dBm · 5 W")
        XCTAssertEqual(RadioSettingsContent.wsprPowerLabel(30), "30 dBm · 1 W")
        XCTAssertEqual(RadioSettingsContent.wsprPowerLabel(23), "23 dBm · 200 mW")
    }

    // MARK: - Waterfall

    func test_occupiedBandwidth_perMode() {
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .ft8), 50.0)
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .ft4), 83.3)
        XCTAssertEqual(WaterfallViewModel.occupiedBandwidthHz(mode: .wspr), 6.0)
    }

    func test_txFrequencyRange_keepsSignalInsideDecoderBand() {
        let range = WaterfallViewModel.txFrequencyRange(mode: .ft4)
        XCTAssertEqual(range.lowerBound, 200)
        XCTAssertEqual(range.upperBound + WaterfallViewModel.occupiedBandwidthHz(mode: .ft4), 3000, accuracy: 1e-9)
    }

    /// WSPR is decoded from raw audio; the slot monitor keeps an FT8
    /// spectrogram so the waterfall still has rows to draw.
    func test_slotMonitorProtocol() {
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .ft8), .ft8)
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .ft4), .ft4)
        XCTAssertEqual(FT8ViewModel.slotMonitorProtocol(for: .wspr), .ft8)
    }

    // MARK: - Dial frequencies

    func test_dialFrequencies() {
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .ft8), 14_074_000)
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .ft4), 14_080_000)
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .wspr), 14_095_600)
        XCTAssertEqual(FT8Message.Band.band2m.frequency(for: .wspr), 144_489_000)
        XCTAssertNil(FT8Message.Band.band33cm.frequency(for: .wspr))
    }

    // MARK: - WSPR spots

    func test_parseWSPRSpot_messageTypes() throws {
        let type1 = try XCTUnwrap(FT8Message.parseWSPRSpot("K1ABC FN42 37".split(separator: " ")))
        XCTAssertEqual(type1.callsign, "K1ABC")
        XCTAssertEqual(type1.locator, "FN42")
        XCTAssertEqual(type1.powerDBm, 37)

        let type2 = try XCTUnwrap(FT8Message.parseWSPRSpot("PJ4/K1ABC 33".split(separator: " ")))
        XCTAssertEqual(type2.callsign, "PJ4/K1ABC")
        XCTAssertNil(type2.locator)

        let type3 = try XCTUnwrap(FT8Message.parseWSPRSpot("<K1ABC> FN42AB 37".split(separator: " ")))
        XCTAssertEqual(type3.callsign, "K1ABC")
        XCTAssertEqual(type3.locator, "FN42AB")
    }

    func test_parseWSPRSpot_rejectsNonSpots() {
        XCTAssertNil(FT8Message.parseWSPRSpot("CQ EA4TST IN80".split(separator: " ")))
        XCTAssertNil(FT8Message.parseWSPRSpot("K1ABC FN42 99".split(separator: " ")))
        XCTAssertNil(FT8Message.parseWSPRSpot("<...> FN42AB 37".split(separator: " ")))
    }

    func test_wsprMessage_isNeverReplyable() {
        let msg = FT8Message(text: "K1ABC FN42 37", mode: .wspr)
        XCTAssertEqual(msg.msgType, .wsprSpot)
        XCTAssertEqual(msg.callsign, "K1ABC")
        XCTAssertFalse(msg.allowsReply)
    }

    /// The spectrogram path never decodes WSPR (it needs the raw samples).
    func test_wspr_snapshotDecodeIsEmpty() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, mode: .ft8)
        XCTAssertTrue(ft8_Engine().decodeWaterfallSnapshot(monitor.snapshotAndReset(), mode: .wspr).isEmpty)
    }
}

// MARK: - WSPRCaptureBuffer

final class WSPRCaptureBufferTests: XCTestCase {

    private let slotStart = Date(timeIntervalSince1970: 1_800_000_000)

    func test_inactive_dropsAudio() {
        let buffer = WSPRCaptureBuffer(sampleRate: 100, maxDuration: 10)
        buffer.append([1, 2, 3])
        XCTAssertFalse(buffer.isActive)
        XCTAssertTrue(buffer.harvest(nextSlotStart: slotStart, now: slotStart).isEmpty)
    }

    /// The first slot after start is not aligned, so it gets no padding.
    func test_firstSlot_isNotPadded() {
        let buffer = WSPRCaptureBuffer(sampleRate: 100, maxDuration: 10)
        buffer.start()
        buffer.append([1, 2, 3])
        XCTAssertEqual(buffer.harvest(nextSlotStart: slotStart, now: slotStart.addingTimeInterval(0.2)), [1, 2, 3])
    }

    /// Audio that arrived between the boundary and the late reset went to the
    /// previous slot, so the next harvest is padded by that long.
    func test_laterSlots_arePaddedToTheBoundary() {
        let buffer = WSPRCaptureBuffer(sampleRate: 100, maxDuration: 10)
        buffer.start()
        _ = buffer.harvest(nextSlotStart: slotStart, now: slotStart.addingTimeInterval(0.2))
        buffer.append([1, 2])
        let next = slotStart.addingTimeInterval(120)
        let harvested = buffer.harvest(nextSlotStart: next, now: next.addingTimeInterval(0.1))
        XCTAssertEqual(harvested.count, 20 + 2)
        XCTAssertEqual(harvested.prefix(20), ArraySlice(repeating: 0, count: 20))
        XCTAssertEqual(harvested.suffix(2), [1, 2])
    }

    /// A boundary missed by seconds (suspension) is not padded.
    func test_largeOffset_isNotPadded() {
        let buffer = WSPRCaptureBuffer(sampleRate: 100, maxDuration: 10)
        buffer.start()
        _ = buffer.harvest(nextSlotStart: slotStart, now: slotStart.addingTimeInterval(30))
        buffer.append([1])
        XCTAssertEqual(buffer.harvest(nextSlotStart: slotStart, now: slotStart), [1])
    }

    func test_capacity_dropsLateAudio() {
        let buffer = WSPRCaptureBuffer(sampleRate: 10, maxDuration: 0.5)
        buffer.start()
        buffer.append([1, 2, 3])
        buffer.append([4, 5, 6])
        XCTAssertEqual(buffer.harvest(nextSlotStart: slotStart, now: slotStart), [1, 2, 3, 4, 5])
    }

    func test_discardCurrentSlot_dropsAudioAndAlignment() {
        let buffer = WSPRCaptureBuffer(sampleRate: 100, maxDuration: 10)
        buffer.start()
        _ = buffer.harvest(nextSlotStart: slotStart, now: slotStart.addingTimeInterval(0.2))
        buffer.append([1, 2])
        buffer.discardCurrentSlot()
        buffer.append([3])
        XCTAssertEqual(buffer.harvest(nextSlotStart: slotStart, now: slotStart), [3])
    }

    func test_stop_freesAudio() {
        let buffer = WSPRCaptureBuffer(sampleRate: 100, maxDuration: 10)
        buffer.start()
        buffer.append([1, 2])
        buffer.stop()
        XCTAssertFalse(buffer.isActive)
        XCTAssertTrue(buffer.harvest(nextSlotStart: slotStart, now: slotStart).isEmpty)
    }

    func test_data_isFloat32() {
        let data = WSPRCaptureBuffer.data(from: [1, -1])
        XCTAssertEqual(data.count, 8)
        let back = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(back, [1, -1])
    }
}
