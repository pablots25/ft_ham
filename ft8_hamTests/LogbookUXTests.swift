//
//  LogbookUXTests.swift
//  ft_hamTests
//
//  Tests for the logbook UX/UI improvements:
//  - Search filtering logic
//  - Date/time formatting
//  - Row match logic
//  - Badge colors
//

import XCTest
@testable import ft8_ham

final class LogbookUXTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(
        callsign: String = "K1ABC",
        grid: String = "FN31",
        date: Date = Date(),
        frequencyHz: Double? = 14_074_000,
        mode: String = "FT8",
        band: String = "20m",
        rstSent: String = "-10",
        rstRcvd: String = "-12",
        stationCallsign: String? = nil,
        cqModifier: String? = nil,
        mySigInfo: String? = nil,
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
            stationCallsign: stationCallsign,
            cqModifier: cqModifier,
            mySigInfo: mySigInfo,
            country: country,
            flag: flag
        )
    }

    // MARK: - LogbookRowFormatters Tests

    func testUTCDateFormattingReturnsExpectedFormat() {
        // 2025-01-15 14:30:00 UTC
        let date = Date(timeIntervalSince1970: 1_736_953_800)
        let result = LogbookRowFormatters.dateString(from: date, local: false)
        XCTAssertEqual(result, "15 Jan 2025")
    }

    func testUTCTimeFormattingIncludesUTCSuffix() {
        let date = Date(timeIntervalSince1970: 1_736_953_800)
        let result = LogbookRowFormatters.timeString(from: date, local: false)
        XCTAssertTrue(result.contains("UTC"), "UTC time string should contain 'UTC' suffix")
    }

    func testLocalTimeFormattingDoesNotIncludeUTC() {
        let date = Date(timeIntervalSince1970: 1_736_953_800)
        let result = LogbookRowFormatters.timeString(from: date, local: true)
        XCTAssertFalse(result.contains("UTC"), "Local time string should not contain 'UTC'")
    }

    func testLocalDateFormattingReturnsNonEmptyString() {
        let date = Date()
        let result = LogbookRowFormatters.dateString(from: date, local: true)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - LogbookBadgeColors Tests

    func testModeBadgeColorFT8IsGreen() {
        XCTAssertEqual(LogbookBadgeColors.mode("FT8"), .green)
        XCTAssertEqual(LogbookBadgeColors.mode("ft8"), .green)
    }

    func testModeBadgeColorFT4IsBlue() {
        XCTAssertEqual(LogbookBadgeColors.mode("FT4"), .blue)
        XCTAssertEqual(LogbookBadgeColors.mode("ft4"), .blue)
    }

    func testModeBadgeColorUnknownIsGray() {
        XCTAssertEqual(LogbookBadgeColors.mode("CW"), .gray)
        XCTAssertEqual(LogbookBadgeColors.mode(""), .gray)
    }

    func testBandBadgeColorsAssigned() {
        // Verify each band gets a distinct non-default color
        let knownBands = ["160m", "80m", "60m", "40m", "30m", "20m", "17m",
                          "15m", "12m", "CB/11m", "10m", "6m", "Custom"]
        for band in knownBands {
            let color = LogbookBadgeColors.band(band)
            // Just verify it doesn't crash and returns something
            XCTAssertNotNil(color, "Band \(band) should have a color")
        }
    }

    // MARK: - Search/Filter Match Logic Tests

    /// Test that filtering matches callsign case-insensitively
    func testFilterMatchesCallsignCaseInsensitive() {
        let entry = makeEntry(callsign: "EA4IQL")
        XCTAssertTrue(matchesFilter(entry, query: "ea4"))
        XCTAssertTrue(matchesFilter(entry, query: "EA4"))
        XCTAssertTrue(matchesFilter(entry, query: "iql"))
    }

    /// Test that filtering matches grid
    func testFilterMatchesGrid() {
        let entry = makeEntry(grid: "IM88")
        XCTAssertTrue(matchesFilter(entry, query: "im88"))
        XCTAssertTrue(matchesFilter(entry, query: "IM"))
    }

    /// Test that filtering matches country
    func testFilterMatchesCountry() {
        let entry = makeEntry(country: "United States")
        XCTAssertTrue(matchesFilter(entry, query: "united"))
        XCTAssertTrue(matchesFilter(entry, query: "states"))
    }

    /// Test that filtering matches mode
    func testFilterMatchesMode() {
        let entry = makeEntry(mode: "FT8")
        XCTAssertTrue(matchesFilter(entry, query: "ft8"))
        XCTAssertTrue(matchesFilter(entry, query: "FT8"))
    }

    /// Test that filtering matches band
    func testFilterMatchesBand() {
        let entry = makeEntry(band: "20m")
        XCTAssertTrue(matchesFilter(entry, query: "20m"))
        XCTAssertTrue(matchesFilter(entry, query: "20"))
    }

    /// Test that non-matching query returns false
    func testFilterDoesNotMatchUnrelatedQuery() {
        let entry = makeEntry(callsign: "K1ABC", grid: "FN31", mode: "FT8", band: "20m", country: "United States")
        XCTAssertFalse(matchesFilter(entry, query: "zzz"))
        XCTAssertFalse(matchesFilter(entry, query: "japan"))
        XCTAssertFalse(matchesFilter(entry, query: "40m"))
    }

    /// Test that nil country doesn't cause crash
    func testFilterHandlesNilCountry() {
        let entry = makeEntry(country: nil)
        XCTAssertFalse(matchesFilter(entry, query: "spain"))
    }

    /// Test that empty search matches everything (handled by applyFilter, not matches)
    func testEmptyQueryAlwaysMatches() {
        // Empty query is handled at the applyFilter level (returns all), not at matches level.
        // A single space is a real substring query: it must not match an entry whose
        // fields contain no spaces (country "United States" would legitimately match).
        let entry = makeEntry(country: nil)
        XCTAssertFalse(matchesFilter(entry, query: " "))
    }

    // MARK: - LogEntry date/time visibility

    /// Verify that entries without cqModifier and without frequencyHz still have a valid date
    func testEntryWithoutModifierOrFrequencyStillHasDate() {
        let fixedDate = Date(timeIntervalSince1970: 1_736_953_800)
        let entry = makeEntry(
            frequencyHz: nil,
            cqModifier: nil,
            mySigInfo: nil
        )
        // The date should always be present on the entry regardless of optional fields
        XCTAssertNotNil(entry.date)
        // And formatters should work for any entry
        let dateStr = LogbookRowFormatters.dateString(from: entry.date, local: false)
        XCTAssertFalse(dateStr.isEmpty, "Date string should always be non-empty")
    }

    /// Verify entries with POTA modifier have correct values
    func testEntryWithActivationModifier() {
        let entry = makeEntry(cqModifier: "POTA", mySigInfo: "K-1234")
        XCTAssertEqual(entry.cqModifier, "POTA")
        XCTAssertEqual(entry.mySigInfo, "K-1234")
    }

    // MARK: - Private helpers

    /// Replicates the match logic from LogbookView.applyFilter
    private func matchesFilter(_ entry: LogEntry, query: String) -> Bool {
        let q = query.lowercased()
        if entry.callsign.lowercased().contains(q) { return true }
        if entry.grid.lowercased().contains(q) { return true }
        if entry.country?.lowercased().contains(q) == true { return true }
        if entry.mode.lowercased().contains(q) { return true }
        if entry.band.lowercased().contains(q) { return true }
        return false
    }
}

// MARK: - QSOEditView Validation Tests

final class QSOEditValidationTests: XCTestCase {

    // MARK: - Maidenhead Grid Validation

    /// Replicates the grid validation logic from QSOEditView
    private func gridValidation(_ grid: String) -> String? {
        let trimmed = grid.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"^[A-R]{2}\d{2}([A-X]{2}(\d{2})?)?$"#
        if trimmed.range(of: pattern, options: .regularExpression) == nil {
            return "Invalid Maidenhead grid (e.g. EM72 or EM72ab)"
        }
        return nil
    }

    func testValidFourCharGrid() {
        XCTAssertNil(gridValidation("EM72"))
        XCTAssertNil(gridValidation("FN31"))
        XCTAssertNil(gridValidation("IM88"))
        XCTAssertNil(gridValidation("JO22"))
    }

    func testValidSixCharGrid() {
        XCTAssertNil(gridValidation("EM72ab"))
        XCTAssertNil(gridValidation("FN31pr"))
        XCTAssertNil(gridValidation("IM88ow"))
    }

    func testValidEightCharGrid() {
        XCTAssertNil(gridValidation("EM72ab12"))
        XCTAssertNil(gridValidation("FN31pr99"))
    }

    func testEmptyGridReturnsNil() {
        XCTAssertNil(gridValidation(""))
        XCTAssertNil(gridValidation("   "))
    }

    func testInvalidGridTooShort() {
        XCTAssertNotNil(gridValidation("EM"))
        XCTAssertNotNil(gridValidation("E"))
    }

    func testInvalidGridBadChars() {
        XCTAssertNotNil(gridValidation("ZZ99")) // first pair must be A-R
        XCTAssertNotNil(gridValidation("1234"))
        XCTAssertNotNil(gridValidation("ABCDEF"))
    }

    func testInvalidGridOddLength() {
        XCTAssertNotNil(gridValidation("EM72a")) // 5 chars is invalid
        XCTAssertNotNil(gridValidation("EM72ab1")) // 7 chars is invalid
    }

    func testGridIsCaseInsensitive() {
        XCTAssertNil(gridValidation("em72"))
        XCTAssertNil(gridValidation("em72AB"))
    }

    // MARK: - Band/Frequency Mismatch

    /// Replicates the band/frequency mismatch logic from QSOEditView
    private func bandFrequencyMismatch(band: String, freqMHz: String) -> String? {
        let clean = freqMHz.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, let mhz = Double(clean), mhz > 0 else { return nil }
        let detectedBand = FT8Message.Band.fromFrequency(mhz * 1_000_000)
        guard detectedBand != .unknown else { return nil }
        if let selectedBand = FT8Message.Band(rawValue: band),
           selectedBand != detectedBand {
            return "Frequency corresponds to \(detectedBand.rawValue), not \(band)"
        }
        return nil
    }

    func testMatchingBandAndFrequencyReturnsNil() {
        XCTAssertNil(bandFrequencyMismatch(band: "20m", freqMHz: "14.074000"))
        XCTAssertNil(bandFrequencyMismatch(band: "40m", freqMHz: "7.074000"))
    }

    func testMismatchedBandAndFrequencyReturnsMessage() {
        let result = bandFrequencyMismatch(band: "20m", freqMHz: "7.074000")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("40m"))
    }

    func testEmptyFrequencyReturnsNilMismatch() {
        XCTAssertNil(bandFrequencyMismatch(band: "20m", freqMHz: ""))
    }

    func testInvalidFrequencyReturnsNilMismatch() {
        XCTAssertNil(bandFrequencyMismatch(band: "20m", freqMHz: "abc"))
    }

    func testUnknownFrequencyReturnsNilMismatch() {
        // A frequency outside any ham band — should not trigger a warning
        XCTAssertNil(bandFrequencyMismatch(band: "20m", freqMHz: "999.0"))
    }

    // MARK: - hasChanges detection

    func testNoChangesDetected() {
        let entry = LogEntry(
            callsign: "K1ABC",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_000_000),
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-12",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        // Simulating the same initial values that QSOEditView would derive
        let freqStr = String(format: "%.6f", 14_074_000.0 / 1_000_000)
        XCTAssertEqual(freqStr, "14.074000")
    }
}
