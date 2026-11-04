//
//  StatisticsHourFormatTests.swift
//  ft8_hamTests
//
//  The Statistics hour labels: 24-hour or 12-hour (AM/PM), never cut to
//  "..." on the Time of Day axis, and day and month names in the user's
//  language.
//

import XCTest
@testable import ft8_ham
#if canImport(FTHamPremium)
import FTHamPremium
#endif

final class StatisticsHourFormatTests: XCTestCase {

    // MARK: - App setting

    func testDefaultsTo24Hour() {
        XCTAssertEqual(StatisticsHourFormat(rawValue: "24h"), .twentyFourHour)
        XCTAssertEqual(StatisticsHourFormat.allCases.first, .twentyFourHour)
    }

    func testStorageKeyIsStable() {
        XCTAssertEqual(StatisticsHourFormat.storageKey, "statisticsHourFormat")
    }

    #if canImport(FTHamPremium)

    private let english = Locale(identifier: "en_US")

    /// The app writes the setting and the premium package reads it.
    func testAppAndPremiumShareKeyAndValues() {
        XCTAssertEqual(StatisticsHourFormat.storageKey, StatsHourFormat.storageKey)
        XCTAssertEqual(StatisticsHourFormat.allCases.map(\.rawValue), StatsHourFormat.allCases.map(\.rawValue))
    }

    // MARK: - Labels

    func test24HourLabelsAreTwoDigits() {
        XCTAssertEqual(StatsHourFormat.twentyFourHour.label(hour: 0), "00")
        XCTAssertEqual(StatsHourFormat.twentyFourHour.label(hour: 9), "09")
        XCTAssertEqual(StatsHourFormat.twentyFourHour.label(hour: 23), "23")
    }

    func test12HourLabelsUseAMAndPM() {
        let format = StatsHourFormat.twelveHour
        XCTAssertEqual(format.label(hour: 0, locale: english), "12 AM")
        XCTAssertEqual(format.label(hour: 6, locale: english), "6 AM")
        XCTAssertEqual(format.label(hour: 12, locale: english), "12 PM")
        XCTAssertEqual(format.label(hour: 18, locale: english), "6 PM")
    }

    /// Chart categories must be unique, or two hours would share a bar.
    func testEveryHourHasItsOwnLabel() {
        for format in StatsHourFormat.allCases {
            let labels = (0..<24).map { format.label(hour: $0, locale: english) }
            XCTAssertEqual(Set(labels).count, 24, "\(format)")
        }
    }

    func testCompactLabelsForTheHeatmap() {
        XCTAssertEqual(StatsHourFormat.twentyFourHour.compactLabel(hour: 15), "15")
        XCTAssertEqual(StatsHourFormat.twelveHour.compactLabel(hour: 0, locale: english), "12a")
        XCTAssertEqual(StatsHourFormat.twelveHour.compactLabel(hour: 15, locale: english), "3p")
    }

    // MARK: - Axis (regression: 24 labels were cut to "...")

    func testAxisLabelsOnlyEveryFewHours() {
        XCTAssertEqual(StatsHourFormat.twentyFourHour.axisHours, [0, 3, 6, 9, 12, 15, 18, 21])
        XCTAssertEqual(StatsHourFormat.twelveHour.axisHours, [0, 4, 8, 12, 16, 20])
    }

    func testAxisNeverLabelsAllHours() {
        for format in StatsHourFormat.allCases {
            XCTAssertLessThanOrEqual(format.axisHours.count, 8, "\(format)")
            XCTAssertTrue(format.axisHours.allSatisfy { (0..<24).contains($0) })
        }
    }

    // MARK: - Records

    /// Busiest Hour is bucketed in UTC, so it is shown in UTC.
    func testRecordHourIsShownInUTC() {
        // 14 March 2026, 18:30 UTC
        let date = Date(timeIntervalSince1970: 1_773_513_000)
        XCTAssertEqual(StatsHourFormat.twentyFourHour.dayAndHour(date, locale: english), "Mar 14, 18:00 UTC")
        XCTAssertEqual(StatsHourFormat.twelveHour.dayAndHour(date, locale: english), "Mar 14, 6 PM UTC")
    }

    // MARK: - Day and month names

    func testWeekdaysAreLocalizedAndStartOnSunday() {
        XCTAssertEqual(StatsCalendarLabels.shortWeekdays(locale: english).first, "Sun")
        XCTAssertEqual(StatsCalendarLabels.shortWeekdays(locale: Locale(identifier: "es_ES")).count, 7)
        XCTAssertNotEqual(
            StatsCalendarLabels.shortWeekdays(locale: Locale(identifier: "de_DE")),
            StatsCalendarLabels.shortWeekdays(locale: english)
        )
    }

    /// Always 12 months, even on a device set to a calendar with 13.
    func testMonthsAreGregorian() {
        XCTAssertEqual(StatsCalendarLabels.shortMonths(locale: Locale(identifier: "he_IL@calendar=hebrew")).count, 12)
        XCTAssertEqual(StatsCalendarLabels.shortMonths(locale: english).first, "Jan")
    }

    #endif
}
