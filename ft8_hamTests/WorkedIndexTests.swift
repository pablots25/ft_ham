//
//  WorkedIndexTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

final class WorkedIndexTests: XCTestCase {

    private func entry(
        _ call: String, grid: String = "FN42", band: String = "20m", mode: String = "FT8",
        country: String? = "United States"
    ) -> LogEntry {
        LogEntry(
            callsign: call, grid: grid, date: Date(), frequencyHz: 14_074_000,
            mode: mode, band: band, rstSent: "-10", rstRcvd: "-12",
            stationCallsign: "EA4IQL", cqModifier: nil, mySigInfo: nil,
            country: country, flag: nil
        )
    }

    func test_build_indexesCallsignGridAndCountryPerBandMode() {
        let index = WorkedIndex.build(from: [
            entry("K1ABC", grid: "FN42xx", band: "20m", mode: "FT8"),
            entry("dl1abc", grid: "JO62", band: "40m", mode: "FT4", country: "Germany"),
        ])

        XCTAssertEqual(index.callsigns, ["K1ABC", "DL1ABC"])
        XCTAssertTrue(index.callsignBandMode.contains("K1ABC|20m|FT8"))
        XCTAssertTrue(index.callsignBandMode.contains("DL1ABC|40m|FT4"))
        XCTAssertFalse(index.callsignBandMode.contains("K1ABC|40m|FT8"))

        // Six-character grids are indexed by their 4-character square.
        XCTAssertTrue(index.gridBandMode.contains("FN42|20m|FT8"))
        XCTAssertTrue(index.gridBandMode.contains("JO62|40m|FT4"))

        XCTAssertTrue(index.countryBandMode.contains("United States|20m|FT8"))
        XCTAssertTrue(index.countryBandMode.contains("Germany|40m|FT4"))
    }

    func test_build_resolvesCountryWhenEntryHasNone() {
        // Older ADIF rows have no cached COUNTRY; the resolver fills it in.
        let index = WorkedIndex.build(from: [entry("EA4IQL", grid: "IN80", country: nil)])
        XCTAssertTrue(index.countryBandMode.contains { $0.hasSuffix("|20m|FT8") })
    }

    func test_build_skipsShortGrids() {
        let index = WorkedIndex.build(from: [entry("K1ABC", grid: "")])
        XCTAssertTrue(index.gridBandMode.isEmpty)
    }

    func test_neededStatus_isOptionSet() {
        var status: NeededStatus = []
        XCTAssertTrue(status.isEmpty)
        status.insert(.grid)
        status.insert(.dxcc)
        XCTAssertTrue(status.contains(.grid))
        XCTAssertTrue(status.contains(.dxcc))
        XCTAssertFalse(status.contains(.callsign))
    }
}
