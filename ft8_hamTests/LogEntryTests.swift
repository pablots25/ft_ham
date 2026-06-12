//
//  LogEntryTests.swift
//  ft_hamTests
//
//  Tests for LogSyncStatus enum and the LogEntry qrzStatus / lotwStatus fields
//  introduced alongside the QRZ Logbook and LoTW premium integration.
//

import XCTest
@testable import ft8_ham

final class LogEntryTests: XCTestCase {

    // MARK: - LogSyncStatus raw values

    func testLogSyncStatusRawValues() {
        XCTAssertEqual(LogSyncStatus.notUploaded.rawValue, "notUploaded")
        XCTAssertEqual(LogSyncStatus.pending.rawValue,     "pending")
        XCTAssertEqual(LogSyncStatus.uploaded.rawValue,    "uploaded")
        XCTAssertEqual(LogSyncStatus.confirmed.rawValue,   "confirmed")
        XCTAssertEqual(LogSyncStatus.duplicate.rawValue,   "duplicate")
        XCTAssertEqual(LogSyncStatus.rejected.rawValue,    "rejected")
    }

    func testLogSyncStatusRoundTripsWithCodable() throws {
        let statuses: [LogSyncStatus] = [
            .notUploaded, .pending, .uploaded, .confirmed, .duplicate, .rejected
        ]
        for status in statuses {
            let data    = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(LogSyncStatus.self, from: data)
            XCTAssertEqual(decoded, status, "\(status) did not round-trip correctly")
        }
    }

    // MARK: - LogEntry default sync statuses

    func testLogEntryDefaultSyncStatusesAreNotUploaded() {
        let entry = makeEntry()
        XCTAssertEqual(entry.qrzStatus,  .notUploaded)
        XCTAssertEqual(entry.lotwStatus, .notUploaded)
    }

    func testLogEntryCanBeInitializedWithCustomSyncStatuses() {
        let entry = makeEntry(qrzStatus: .confirmed, lotwStatus: .uploaded)
        XCTAssertEqual(entry.qrzStatus,  .confirmed)
        XCTAssertEqual(entry.lotwStatus, .uploaded)
    }

    func testLogEntrySyncStatusesAreMutable() {
        var entry = makeEntry()
        XCTAssertEqual(entry.qrzStatus,  .notUploaded)
        XCTAssertEqual(entry.lotwStatus, .notUploaded)

        entry.qrzStatus  = .uploaded
        entry.lotwStatus = .confirmed

        XCTAssertEqual(entry.qrzStatus,  .uploaded)
        XCTAssertEqual(entry.lotwStatus, .confirmed)
    }

    func testLogEntryAllSyncStatusCombinations() {
        let allStatuses: [LogSyncStatus] = [
            .notUploaded, .pending, .uploaded, .confirmed, .duplicate, .rejected
        ]
        for qrz in allStatuses {
            for lotw in allStatuses {
                let entry = makeEntry(qrzStatus: qrz, lotwStatus: lotw)
                XCTAssertEqual(entry.qrzStatus,  qrz)
                XCTAssertEqual(entry.lotwStatus, lotw)
            }
        }
    }

    // MARK: - Existing init compatibility (no regression from default params)

    func testLogEntryOmittingStatusParamsCompiles() {
        // Verifies backward-compat: code that doesn't pass the new params still works.
        let entry = LogEntry(
            callsign: "EA4IQL",
            grid:     "IM88",
            date:     Date(),
            frequencyHz: nil,
            mode:     "FT8",
            band:     "20m",
            rstSent:  "-10",
            rstRcvd:  "-12",
            stationCallsign: nil,
            cqModifier:      nil,
            mySigInfo:       nil,
            country:         nil,
            flag:            nil
            // qrzStatus and lotwStatus intentionally omitted → use defaults
        )
        XCTAssertEqual(entry.qrzStatus,  .notUploaded)
        XCTAssertEqual(entry.lotwStatus, .notUploaded)
    }

    // MARK: - Helper

    private func makeEntry(
        qrzStatus:  LogSyncStatus = .notUploaded,
        lotwStatus: LogSyncStatus = .notUploaded
    ) -> LogEntry {
        LogEntry(
            callsign:        "K1ABC",
            grid:            "FN31",
            date:            Date(),
            frequencyHz:     14_074_000,
            mode:            "FT8",
            band:            "20m",
            rstSent:         "-10",
            rstRcvd:         "-12",
            stationCallsign: nil,
            cqModifier:      nil,
            mySigInfo:       nil,
            country:         "United States",
            flag:            "🇺🇸",
            qrzStatus:       qrzStatus,
            lotwStatus:      lotwStatus
        )
    }
}
