//
//  CustomFrequencyTests.swift
//  ft8_hamTests
//

import XCTest
@testable import ft8_ham

@MainActor
final class CustomFrequencyTests: XCTestCase {

    // MARK: - Band.fromFrequency

    func testFromFrequency_160m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(1_840_000), .band160m)
        XCTAssertEqual(FT8Message.Band.fromFrequency(1_900_000), .band160m)
    }

    func testFromFrequency_80m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(3_573_000), .band80m)
        XCTAssertEqual(FT8Message.Band.fromFrequency(3_700_000), .band80m)
    }

    func testFromFrequency_60m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(5_357_000), .band60m)
    }

    func testFromFrequency_40m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(7_074_000), .band40m)
        XCTAssertEqual(FT8Message.Band.fromFrequency(7_200_000), .band40m)
    }

    func testFromFrequency_30m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(10_136_000), .band30m)
    }

    func testFromFrequency_20m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(14_074_000), .band20m)
        XCTAssertEqual(FT8Message.Band.fromFrequency(14_250_000), .band20m)
        XCTAssertEqual(FT8Message.Band.fromFrequency(14_000_000), .band20m)
    }

    func testFromFrequency_17m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(18_100_000), .band17m)
    }

    func testFromFrequency_15m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(21_074_000), .band15m)
    }

    func testFromFrequency_12m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(24_915_000), .band12m)
    }

    func testFromFrequency_11m_CB() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(27_245_000), .band11m)
    }

    func testFromFrequency_10m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(28_074_000), .band10m)
        XCTAssertEqual(FT8Message.Band.fromFrequency(29_000_000), .band10m)
    }

    func testFromFrequency_6m() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(50_313_000), .band6m)
        XCTAssertEqual(FT8Message.Band.fromFrequency(51_000_000), .band6m)
    }

    func testFromFrequency_unknown_belowAllBands() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(1_000_000), .unknown)
    }

    func testFromFrequency_unknown_betweenBands() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(4_500_000), .unknown)   // between 80m and 60m
        XCTAssertEqual(FT8Message.Band.fromFrequency(6_000_000), .unknown)   // between 60m and 40m
    }

    func testFromFrequency_unknown_aboveAllBands() {
        XCTAssertEqual(FT8Message.Band.fromFrequency(200_000_000), .unknown)
    }

    // MARK: - Band.custom membership

    func testCustomBandIncludedInValidBands() {
        XCTAssertTrue(FT8Message.Band.validBands.contains(.custom))
    }

    func testUnknownBandNotInValidBands() {
        XCTAssertFalse(FT8Message.Band.validBands.contains(.unknown))
    }

    func testCustomBandFrequencyReturnsNil() {
        XCTAssertNil(FT8Message.Band.custom.frequency(for: .ft8))
        XCTAssertNil(FT8Message.Band.custom.frequency(for: .ft4))
    }

    // MARK: - LogEntry with custom dial frequency

    func testLogEntry_withFrequencyHz_isStored() {
        let entry = LogEntry(
            callsign: "EA1AA",
            grid: "IN80",
            date: Date(),
            frequencyHz: 14_250_000,
            mode: "FT8",
            band: "20m",
            rstSent: "12",
            rstRcvd: "-4",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        XCTAssertEqual(entry.frequencyHz, 14_250_000)
    }

    func testLogEntry_withoutFrequencyHz_isNil() {
        let entry = LogEntry(
            callsign: "EA1AA",
            grid: "IN80",
            date: Date(),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "12",
            rstRcvd: "-4",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        XCTAssertNil(entry.frequencyHz)
    }

    // MARK: - ADIF export with custom frequency

    func testADIF_exportIncludesFREQ_whenFrequencyHzIsSet() {
        let manager = LogbookManager()
        let date = Date(timeIntervalSince1970: 1_700_000_123)
        let entry = LogEntry(
            callsign: "EA1AA",
            grid: "IN80",
            date: date,
            frequencyHz: 14_250_000,
            mode: "FT8",
            band: "20m",
            rstSent: "12",
            rstRcvd: "-4",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        guard let url = manager.saveToADIF([entry]),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Failed to save or read ADIF")
            return
        }
        XCTAssertTrue(content.contains("<FREQ:"), "ADIF should contain FREQ field")
        XCTAssertTrue(content.contains("14.250000"), "FREQ should be in MHz")
    }

    func testADIF_exportOmitsFREQ_whenFrequencyHzIsNil() {
        let manager = LogbookManager()
        let date = Date(timeIntervalSince1970: 1_700_000_123)
        let entry = LogEntry(
            callsign: "EA1AA",
            grid: "IN80",
            date: date,
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "12",
            rstRcvd: "-4",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        guard let url = manager.saveToADIF([entry]),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Failed to save or read ADIF")
            return
        }
        XCTAssertFalse(content.contains("<FREQ:"), "ADIF should NOT contain FREQ when frequencyHz is nil")
    }

    // MARK: - effectiveBand in ViewModel

    func testEffectiveBand_nonCustom_returnsSelf() {
        let vm = FT8ViewModel()
        vm.selectedBand = .band20m
        XCTAssertEqual(vm.effectiveBand, .band20m)
    }

    func testEffectiveBand_custom_detectsFrom20m() {
        let vm = FT8ViewModel()
        vm.selectedBand = .custom
        vm.customDialFrequencyHz = 14_074_000
        XCTAssertEqual(vm.effectiveBand, .band20m)
    }

    func testEffectiveBand_custom_detectsFrom40m() {
        let vm = FT8ViewModel()
        vm.selectedBand = .custom
        vm.customDialFrequencyHz = 7_074_000
        XCTAssertEqual(vm.effectiveBand, .band40m)
    }

    func testEffectiveBand_custom_detectsCBBand() {
        let vm = FT8ViewModel()
        vm.selectedBand = .custom
        vm.customDialFrequencyHz = 27_245_000
        XCTAssertEqual(vm.effectiveBand, .band11m)
    }

    func testEffectiveBand_custom_unknownOutOfBand() {
        let vm = FT8ViewModel()
        vm.selectedBand = .custom
        vm.customDialFrequencyHz = 100_000_000
        XCTAssertEqual(vm.effectiveBand, .unknown)
    }

    // MARK: - ADIF BAND omission for Unknown band

    func testADIF_omitsBAND_whenBandIsUnknown() {
        let manager = LogbookManager()
        let entry = LogEntry(
            callsign: "W1AW",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 4_630_000,
            mode: "FT8",
            band: "Unknown",
            rstSent: "-10",
            rstRcvd: "-14",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        guard let url = manager.saveToADIF([entry]),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Failed to save or read ADIF")
            return
        }
        XCTAssertFalse(content.contains("<BAND:"), "ADIF should NOT contain BAND field when band is Unknown")
        XCTAssertTrue(content.contains("<FREQ:"), "ADIF should still contain FREQ field")
        XCTAssertTrue(content.contains("4.630000"), "FREQ should show the custom frequency in MHz")
    }

    func testADIF_includesBAND_whenBandIsKnownAndCustomFrequency() {
        let manager = LogbookManager()
        let entry = LogEntry(
            callsign: "G3ZAY",
            grid: "IO91",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 14_100_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-05",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        guard let url = manager.saveToADIF([entry]),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Failed to save or read ADIF")
            return
        }
        XCTAssertTrue(content.contains("<BAND:3>20m"), "ADIF should contain BAND field for known band")
        XCTAssertTrue(content.contains("<FREQ:"), "ADIF should contain FREQ field")
        XCTAssertTrue(content.contains("14.100000"), "FREQ should show the custom frequency in MHz")
    }
}
