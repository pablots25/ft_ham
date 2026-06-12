//
//  StatisticsEngineTests.swift
//  ft8_hamTests
//
//  Created by Copilot on 13/04/26.
//

import XCTest
@testable import ft8_ham

final class StatisticsEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(
        callsign: String = "W1AW",
        grid: String = "FN31",
        date: Date = Date(),
        frequencyHz: Double? = 14_074_000,
        mode: String = "FT8",
        band: String = "20m",
        rstSent: String = "-10",
        rstRcvd: String = "-12",
        country: String? = "United States",
        flag: String? = "🇺🇸"
    ) -> LogEntry {
        LogEntry(
            callsign: callsign,
            grid: grid,
            date: date,
            frequencyHz: frequencyHz,
            mode: mode,
            band: band,
            rstSent: rstSent,
            rstRcvd: rstRcvd,
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: country,
            flag: flag
        )
    }

    // MARK: - Empty log

    func testEmptyLogProducesZeroSummary() {
        let summary = StatisticsEngine.compute(entries: [], period: .allTime)

        XCTAssertEqual(summary.totalQSOs, 0)
        XCTAssertEqual(summary.uniqueCallsigns, 0)
        XCTAssertEqual(summary.uniqueCountries, 0)
        XCTAssertEqual(summary.uniqueGrids, 0)
        XCTAssertEqual(summary.uniqueBands, 0)
        XCTAssertNil(summary.firstQSO)
        XCTAssertNil(summary.latestQSO)
        XCTAssertNil(summary.avgSnrReceived)
        XCTAssertTrue(summary.qsosByBand.isEmpty)
        XCTAssertTrue(summary.qsosByMode.isEmpty)
        XCTAssertTrue(summary.qsosByCountry.isEmpty)
        XCTAssertTrue(summary.activitySeries.isEmpty)
    }

    // MARK: - Single QSO

    func testSingleQSOCounts() {
        let entries = [makeEntry()]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)

        XCTAssertEqual(summary.totalQSOs, 1)
        XCTAssertEqual(summary.uniqueCallsigns, 1)
        XCTAssertEqual(summary.uniqueCountries, 1)
        XCTAssertEqual(summary.uniqueGrids, 1)
        XCTAssertEqual(summary.uniqueBands, 1)
        XCTAssertNotNil(summary.firstQSO)
        XCTAssertNotNil(summary.latestQSO)
    }

    // MARK: - Unique counts with duplicates

    func testUniqueCountsDeduplicateCorrectly() {
        let entries = [
            makeEntry(callsign: "W1AW", grid: "FN31", band: "20m", country: "United States"),
            makeEntry(callsign: "W1AW", grid: "FN31", band: "20m", country: "United States"),  // duplicate
            makeEntry(callsign: "EA4IQL", grid: "IN80", band: "40m", country: "Spain"),
            makeEntry(callsign: "JA1ABC", grid: "PM95", band: "20m", country: "Japan"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)

        XCTAssertEqual(summary.totalQSOs, 4)
        XCTAssertEqual(summary.uniqueCallsigns, 3)
        XCTAssertEqual(summary.uniqueCountries, 3)
        XCTAssertEqual(summary.uniqueGrids, 3)
        XCTAssertEqual(summary.uniqueBands, 2)
    }

    // MARK: - Band grouping

    func testQSOsByBandSortedByCount() {
        let entries = [
            makeEntry(band: "20m"),
            makeEntry(band: "20m"),
            makeEntry(band: "20m"),
            makeEntry(band: "40m"),
            makeEntry(band: "40m"),
            makeEntry(band: "10m"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)

        XCTAssertEqual(summary.qsosByBand.count, 3)
        XCTAssertEqual(summary.qsosByBand[0].key, "20m")
        XCTAssertEqual(summary.qsosByBand[0].count, 3)
        XCTAssertEqual(summary.qsosByBand[1].key, "40m")
        XCTAssertEqual(summary.qsosByBand[1].count, 2)
        XCTAssertEqual(summary.qsosByBand[2].key, "10m")
        XCTAssertEqual(summary.qsosByBand[2].count, 1)
    }

    // MARK: - Mode grouping

    func testQSOsByMode() {
        let entries = [
            makeEntry(mode: "FT8"),
            makeEntry(mode: "FT8"),
            makeEntry(mode: "FT4"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)

        XCTAssertEqual(summary.qsosByMode.count, 2)
        XCTAssertEqual(summary.qsosByMode[0].key, "FT8")
        XCTAssertEqual(summary.qsosByMode[0].count, 2)
        XCTAssertEqual(summary.qsosByMode[1].key, "FT4")
        XCTAssertEqual(summary.qsosByMode[1].count, 1)
    }

    // MARK: - Country ranking

    func testTopCountriesLimitedTo20() {
        var entries = [LogEntry]()
        for i in 0..<25 {
            entries.append(makeEntry(country: "Country \(i)", flag: "🏳️"))
        }
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.qsosByCountry.count, 20)
    }

    func testCountriesWithNilAreExcluded() {
        let entries = [
            makeEntry(country: "Spain", flag: "🇪🇸"),
            makeEntry(country: nil, flag: nil),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.qsosByCountry.count, 1)
    }

    // MARK: - Hour distribution

    func testByHourReturns24Entries() {
        let entries = [makeEntry()]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.qsosByHour.count, 24)
    }

    // MARK: - Period filtering

    func testFilterLast7DaysExcludesOlderEntries() {
        let recent = makeEntry(date: Date())
        let old = makeEntry(date: Calendar.current.date(byAdding: .day, value: -10, to: Date())!)

        let summary = StatisticsEngine.compute(entries: [recent, old], period: .last7Days)
        XCTAssertEqual(summary.totalQSOs, 1)
    }

    func testFilterThisYearExcludesLastYear() {
        let thisYear = makeEntry(date: Date())

        var comps = DateComponents()
        comps.year = Calendar.current.component(.year, from: Date()) - 1
        comps.month = 6
        comps.day = 15
        let lastYearDate = Calendar.current.date(from: comps)!
        let lastYear = makeEntry(date: lastYearDate)

        let summary = StatisticsEngine.compute(entries: [thisYear, lastYear], period: .thisYear)
        XCTAssertEqual(summary.totalQSOs, 1)
    }

    func testFilterCustomRange() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let end = cal.date(from: DateComponents(year: 2025, month: 6, day: 30))!

        let inside = makeEntry(date: cal.date(from: DateComponents(year: 2025, month: 6, day: 15))!)
        let outside = makeEntry(date: cal.date(from: DateComponents(year: 2025, month: 7, day: 5))!)

        let summary = StatisticsEngine.compute(entries: [inside, outside], period: .custom(start, end))
        XCTAssertEqual(summary.totalQSOs, 1)
    }

    // MARK: - Activity series granularity

    func testActivitySeriesDailyForLast7Days() {
        XCTAssertTrue(StatisticsEngine.shouldUseDailyGranularity(.last7Days))
        XCTAssertTrue(StatisticsEngine.shouldUseDailyGranularity(.last30Days))
        XCTAssertTrue(StatisticsEngine.shouldUseDailyGranularity(.thisMonth))
    }

    func testActivitySeriesMonthlyForAllTime() {
        XCTAssertFalse(StatisticsEngine.shouldUseDailyGranularity(.allTime))
        XCTAssertFalse(StatisticsEngine.shouldUseDailyGranularity(.thisYear))
    }

    // MARK: - SNR parsing

    func testParseSnrValues() {
        XCTAssertEqual(StatisticsEngine.parseSnr("-12"), -12)
        XCTAssertEqual(StatisticsEngine.parseSnr("+05"), 5)
        XCTAssertEqual(StatisticsEngine.parseSnr("0"), 0)
        XCTAssertNil(StatisticsEngine.parseSnr(""))
        XCTAssertNil(StatisticsEngine.parseSnr("abc"))
    }

    func testAverageSnr() {
        let entries = [
            makeEntry(rstRcvd: "-10"),
            makeEntry(rstRcvd: "-6"),
            makeEntry(rstRcvd: "+2"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        // Average of -10, -6, +2 = -14/3 ≈ -4.67
        XCTAssertNotNil(summary.avgSnrReceived)
        XCTAssertEqual(summary.avgSnrReceived!, -14.0 / 3.0, accuracy: 0.01)
    }

    func testSnrBucketsCount() {
        let entries = [makeEntry(rstRcvd: "-12")]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.snrBuckets.count, 7)
    }

    // MARK: - Case-insensitive callsign dedup

    func testCallsignDeduplicationIsCaseInsensitive() {
        let entries = [
            makeEntry(callsign: "W1AW"),
            makeEntry(callsign: "w1aw"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.uniqueCallsigns, 1)
    }

    // MARK: - Grid to coordinate

    func testGridToCoordinateFourChar() {
        let coord = StatisticsEngine.gridToCoordinate("FN31")
        XCTAssertNotNil(coord)
        // FN31 should be roughly lat ~41.5, lon ~-72 (Connecticut area)
        XCTAssertEqual(coord!.lat, 41.5, accuracy: 1.0)
        XCTAssertEqual(coord!.lon, -73.0, accuracy: 2.0)
    }

    func testGridToCoordinateSixChar() {
        let coord = StatisticsEngine.gridToCoordinate("IN80du")
        XCTAssertNotNil(coord)
        // IN80 should be roughly lat ~40, lon ~-3 (Madrid area)
        XCTAssertEqual(coord!.lat, 40.5, accuracy: 1.5)
        XCTAssertEqual(coord!.lon, -3.0, accuracy: 2.0)
    }

    func testGridToCoordinateInvalid() {
        XCTAssertNil(StatisticsEngine.gridToCoordinate(""))
        XCTAssertNil(StatisticsEngine.gridToCoordinate("XX"))
        XCTAssertNil(StatisticsEngine.gridToCoordinate("123"))
    }

    // MARK: - Haversine distance

    func testHaversineKnownDistance() {
        // Madrid to New York: roughly 5761 km
        let d = StatisticsEngine.haversineKm(lat1: 40.4, lon1: -3.7, lat2: 40.7, lon2: -74.0)
        XCTAssertEqual(d, 5760, accuracy: 200)
    }

    func testHaversineZeroDistance() {
        let d = StatisticsEngine.haversineKm(lat1: 40.0, lon1: -3.0, lat2: 40.0, lon2: -3.0)
        XCTAssertEqual(d, 0, accuracy: 0.01)
    }

    // MARK: - Distance stats

    func testDistanceStatsWithGrid() {
        let entries = [
            makeEntry(callsign: "W1AW", grid: "FN31"),
            makeEntry(callsign: "JA1ABC", grid: "PM95"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime, myGrid: "IN80")
        XCTAssertNotNil(summary.distanceStats)
        XCTAssertEqual(summary.distanceStats!.qsoCount, 2)
        XCTAssertGreaterThan(summary.distanceStats!.maxKm, 0)
    }

    func testDistanceStatsNilWithoutMyGrid() {
        let entries = [makeEntry(grid: "FN31")]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime, myGrid: "")
        XCTAssertNil(summary.distanceStats)
    }

    // MARK: - Best DX

    func testBestDXSortedByDistance() {
        let entries = [
            makeEntry(callsign: "W1AW", grid: "FN31"),
            makeEntry(callsign: "JA1ABC", grid: "PM95"),
            makeEntry(callsign: "VK2ABC", grid: "QF56"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime, myGrid: "IN80")
        XCTAssertFalse(summary.bestDX.isEmpty)
        // Should be sorted descending by distance
        for i in 1..<summary.bestDX.count {
            XCTAssertGreaterThanOrEqual(summary.bestDX[i - 1].distanceKm, summary.bestDX[i].distanceKm)
        }
    }

    // MARK: - Day of week

    func testDayOfWeekReturns7Entries() {
        let entries = [makeEntry()]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.qsosByDayOfWeek.count, 7)
    }

    // MARK: - Top callsigns

    func testTopCallsignsLimitedTo10() {
        var entries = [LogEntry]()
        for i in 0..<20 {
            entries.append(makeEntry(callsign: "CALL\(i)"))
        }
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.topCallsigns.count, 10)
    }

    func testTopCallsignsSortedByCount() {
        let entries = [
            makeEntry(callsign: "W1AW"),
            makeEntry(callsign: "W1AW"),
            makeEntry(callsign: "W1AW"),
            makeEntry(callsign: "EA4IQL"),
            makeEntry(callsign: "EA4IQL"),
            makeEntry(callsign: "JA1ABC"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.topCallsigns[0].callsign, "W1AW")
        XCTAssertEqual(summary.topCallsigns[0].count, 3)
    }

    // MARK: - Operating streaks

    func testStreaksConsecutiveDays() {
        let cal = Calendar.current
        let entries = [
            makeEntry(date: cal.date(byAdding: .day, value: -2, to: Date())!),
            makeEntry(date: cal.date(byAdding: .day, value: -1, to: Date())!),
            makeEntry(date: Date()),
        ]
        let (longest, current) = StatisticsEngine.operatingStreaks(entries.sorted { $0.date < $1.date })
        XCTAssertGreaterThanOrEqual(longest, 3)
        XCTAssertGreaterThanOrEqual(current, 1)
    }

    func testStreaksWithGap() {
        let cal = Calendar.current
        let entries = [
            makeEntry(date: cal.date(byAdding: .day, value: -10, to: Date())!),
            makeEntry(date: cal.date(byAdding: .day, value: -5, to: Date())!),
        ]
        let (longest, _) = StatisticsEngine.operatingStreaks(entries.sorted { $0.date < $1.date })
        XCTAssertEqual(longest, 1)
    }

    // MARK: - Continent from coords

    func testContinentFromCoords() {
        XCTAssertEqual(StatisticsEngine.continentFromCoords(lat: 40.4, lon: -3.7), "EU")
        XCTAssertEqual(StatisticsEngine.continentFromCoords(lat: 40.7, lon: -74.0), "NA")
        XCTAssertEqual(StatisticsEngine.continentFromCoords(lat: 35.6, lon: 139.7), "AS")
        XCTAssertEqual(StatisticsEngine.continentFromCoords(lat: -33.8, lon: 151.2), "OC")
        XCTAssertEqual(StatisticsEngine.continentFromCoords(lat: -23.5, lon: -46.6), "SA")
    }

    // MARK: - CQ modifier breakdown

    func testCQModifierBreakdown() {
        let entries = [
            makeEntry(),  // nil cqModifier → "Standard CQ"
            makeEntry(),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertFalse(summary.qsosByCQModifier.isEmpty)
        XCTAssertEqual(summary.qsosByCQModifier.first?.key, "Standard CQ")
    }

    // MARK: - Grid field heatmap

    func testGridFieldHeatmap() {
        let entries = [
            makeEntry(grid: "FN31"),
            makeEntry(grid: "FN42"),
            makeEntry(grid: "IN80"),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.gridFieldHeatmap.count, 2) // FN and IN
        XCTAssertEqual(summary.gridFieldHeatmap.first?.field, "FN") // FN has 2 entries
        XCTAssertEqual(summary.gridFieldHeatmap.first?.count, 2)
    }

    // MARK: - Continent breakdown in summary

    func testContinentBreakdownPopulated() {
        let entries = [
            makeEntry(grid: "FN31"),  // NA
            makeEntry(grid: "IN80"),  // EU
            makeEntry(grid: "PM95"),  // AS
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.qsosByContinent.count, 3)
    }

    // MARK: - Year over year

    func testYearOverYearGroupsByMonth() {
        let cal = Calendar.current
        let entries = [
            makeEntry(date: cal.date(from: DateComponents(year: 2024, month: 6, day: 15))!),
            makeEntry(date: cal.date(from: DateComponents(year: 2025, month: 6, day: 15))!),
        ]
        let summary = StatisticsEngine.compute(entries: entries, period: .allTime)
        XCTAssertEqual(summary.yearOverYear.count, 2)
    }
}
