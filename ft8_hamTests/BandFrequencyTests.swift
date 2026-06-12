// BandFrequencyTests.swift
// ft8_hamTests
//
// Tests for FT8Message.Band.frequency(for:), Band.validBands,
// and the round-trip property: band.frequency(for:.ft8) → Band.fromFrequency() → same band.
//
// All tested code is pure/deterministic — no @MainActor required.

import XCTest
@testable import ft8_ham

/// Tests for `FT8Message.Band` dial-frequency lookup and round-trip consistency.
final class BandFrequencyTests: XCTestCase {

    // MARK: - FT8 dial frequencies

    func test_frequency_ft8_160m_is1840kHz() {
        XCTAssertEqual(FT8Message.Band.band160m.frequency(for: .ft8), 1_840_000)
    }

    func test_frequency_ft8_80m_is3573kHz() {
        XCTAssertEqual(FT8Message.Band.band80m.frequency(for: .ft8), 3_573_000)
    }

    func test_frequency_ft8_60m_is5357kHz() {
        XCTAssertEqual(FT8Message.Band.band60m.frequency(for: .ft8), 5_357_000)
    }

    func test_frequency_ft8_40m_is7074kHz() {
        XCTAssertEqual(FT8Message.Band.band40m.frequency(for: .ft8), 7_074_000)
    }

    func test_frequency_ft8_30m_is10136kHz() {
        XCTAssertEqual(FT8Message.Band.band30m.frequency(for: .ft8), 10_136_000)
    }

    func test_frequency_ft8_20m_is14074kHz() {
        XCTAssertEqual(FT8Message.Band.band20m.frequency(for: .ft8), 14_074_000)
    }

    func test_frequency_ft8_17m_is18100kHz() {
        XCTAssertEqual(FT8Message.Band.band17m.frequency(for: .ft8), 18_100_000)
    }

    func test_frequency_ft8_15m_is21074kHz() {
        XCTAssertEqual(FT8Message.Band.band15m.frequency(for: .ft8), 21_074_000)
    }

    func test_frequency_ft8_12m_is24915kHz() {
        XCTAssertEqual(FT8Message.Band.band12m.frequency(for: .ft8), 24_915_000)
    }

    func test_frequency_ft8_11m_is27245kHz() {
        XCTAssertEqual(FT8Message.Band.band11m.frequency(for: .ft8), 27_245_000)
    }

    func test_frequency_ft8_10m_is28074kHz() {
        XCTAssertEqual(FT8Message.Band.band10m.frequency(for: .ft8), 28_074_000)
    }

    func test_frequency_ft8_6m_is50313kHz() {
        XCTAssertEqual(FT8Message.Band.band6m.frequency(for: .ft8), 50_313_000)
    }

    func test_frequency_ft8_custom_isNil() {
        XCTAssertNil(FT8Message.Band.custom.frequency(for: .ft8))
    }

    func test_frequency_ft8_unknown_isNil() {
        XCTAssertNil(FT8Message.Band.unknown.frequency(for: .ft8))
    }

    // MARK: - FT4 dial frequencies (distinct from FT8 where the protocol differs)

    func test_frequency_ft4_80m_is3575kHz_differentFrom_ft8() {
        let ft4 = FT8Message.Band.band80m.frequency(for: .ft4)
        let ft8 = FT8Message.Band.band80m.frequency(for: .ft8)
        XCTAssertEqual(ft4, 3_575_000)
        XCTAssertNotEqual(ft4, ft8, "FT4 and FT8 80m frequencies must differ")
    }

    func test_frequency_ft4_40m_is7047_5kHz() {
        XCTAssertEqual(FT8Message.Band.band40m.frequency(for: .ft4), 7_047_500)
    }

    func test_frequency_ft4_30m_is10140kHz() {
        XCTAssertEqual(FT8Message.Band.band30m.frequency(for: .ft4), 10_140_000)
    }

    func test_frequency_ft4_20m_is14080kHz() {
        let ft4 = FT8Message.Band.band20m.frequency(for: .ft4)
        XCTAssertEqual(ft4, 14_080_000)
        XCTAssertNotEqual(ft4, FT8Message.Band.band20m.frequency(for: .ft8))
    }

    func test_frequency_ft4_17m_is18104kHz() {
        XCTAssertEqual(FT8Message.Band.band17m.frequency(for: .ft4), 18_104_000)
    }

    func test_frequency_ft4_15m_is21140kHz() {
        XCTAssertEqual(FT8Message.Band.band15m.frequency(for: .ft4), 21_140_000)
    }

    func test_frequency_ft4_12m_is24919kHz() {
        XCTAssertEqual(FT8Message.Band.band12m.frequency(for: .ft4), 24_919_000)
    }

    func test_frequency_ft4_10m_is28180kHz() {
        XCTAssertEqual(FT8Message.Band.band10m.frequency(for: .ft4), 28_180_000)
    }

    func test_frequency_ft4_6m_is50318kHz() {
        XCTAssertEqual(FT8Message.Band.band6m.frequency(for: .ft4), 50_318_000)
    }

    func test_frequency_ft4_custom_isNil() {
        XCTAssertNil(FT8Message.Band.custom.frequency(for: .ft4))
    }

    func test_frequency_ft4_unknown_isNil() {
        XCTAssertNil(FT8Message.Band.unknown.frequency(for: .ft4))
    }

    // MARK: - validBands contract

    func test_validBands_excludesUnknown() {
        XCTAssertFalse(FT8Message.Band.validBands.contains(.unknown))
    }

    func test_validBands_includesCustom() {
        XCTAssertTrue(FT8Message.Band.validBands.contains(.custom))
    }

    func test_validBands_count_is13() {
        // 12 standard amateur bands + custom = 13; unknown is excluded
        XCTAssertEqual(FT8Message.Band.validBands.count, 13)
    }

    func test_validBands_containsAllStandardBands() {
        let standard: [FT8Message.Band] = [
            .band160m, .band80m, .band60m, .band40m, .band30m, .band20m,
            .band17m, .band15m, .band12m, .band11m, .band10m, .band6m
        ]
        for band in standard {
            XCTAssertTrue(FT8Message.Band.validBands.contains(band), "\(band) missing from validBands")
        }
    }

    // MARK: - Round-trip: frequency(for: .ft8) → fromFrequency → same band

    /// For every standard band (excluding custom/unknown and 11m CB which sits in a non-amateur
    /// ITU range), feeding its FT8 dial frequency back through `fromFrequency` must return the
    /// original band. This catches any accidental overlap in the switch ranges.
    func test_roundTrip_ft8DialFrequency_returnsOriginalBand() {
        // 11m (CB) is included since 27.245 MHz falls in the 26.96–27.41 range
        let standardBands: [FT8Message.Band] = [
            .band160m, .band80m, .band60m, .band40m, .band30m, .band20m,
            .band17m, .band15m, .band12m, .band11m, .band10m, .band6m
        ]

        for band in standardBands {
            guard let hz = band.frequency(for: .ft8) else {
                XCTFail("\(band.rawValue) has no FT8 frequency")
                continue
            }
            let detected = FT8Message.Band.fromFrequency(hz)
            XCTAssertEqual(detected, band,
                           "Round-trip failed for \(band.rawValue): \(hz) Hz → \(detected.rawValue)")
        }
    }

    /// FT4 frequencies that differ from FT8 should also round-trip correctly.
    func test_roundTrip_ft4DialFrequency_returnsOriginalBand() {
        let bandsWithDistinctFT4: [FT8Message.Band] = [
            .band80m, .band40m, .band30m, .band20m, .band17m,
            .band15m, .band12m, .band10m, .band6m
        ]

        for band in bandsWithDistinctFT4 {
            guard let hz = band.frequency(for: .ft4) else { continue }
            let detected = FT8Message.Band.fromFrequency(hz)
            XCTAssertEqual(detected, band,
                           "FT4 round-trip failed for \(band.rawValue): \(hz) Hz → \(detected.rawValue)")
        }
    }
}
