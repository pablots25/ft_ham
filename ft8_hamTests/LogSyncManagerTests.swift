//
//  LogSyncManagerTests.swift
//  ft_hamTests
//
//  Tests for LogSyncManager: ADIF generation, syncNewQSO upload routing,
//  pending-ID lifecycle, and retryPendingUploads — all using injected mocks.
//

import XCTest
import Combine
@testable import ft8_ham

@MainActor
final class LogSyncManagerTests: XCTestCase {

    private var mockQRZ:  MockQRZService!
    private var mockLoTW: MockLoTWService!
    private var mockEQSL: MockEQSLService!
    private var manager:  LogSyncManager!

    override func setUp() async throws {
        mockQRZ  = MockQRZService()
        mockLoTW = MockLoTWService()
        mockEQSL = MockEQSLService()
        manager  = LogSyncManager(qrzService: mockQRZ, lotwService: mockLoTW, eqslService: mockEQSL)
    }

    override func tearDown() async throws {
        // Remove UserDefaults keys written during tests.
        for key in ["qrzAutoUpload", "lotwAutoUpload", "eqslAutoUpload",
                    "qrzConfirmationIntervalHours",
                    "pendingQRZIDs", "pendingLoTWIDs", "pendingEQSLIDs"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        manager  = nil
        mockQRZ  = nil
        mockLoTW = nil
        mockEQSL = nil
    }

    // MARK: - buildSingleEntryADIF — field presence

    func testBuildADIF_ContainsRequiredFields() {
        let date  = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let entry = makeEntry(callsign: "K1ABC", date: date, frequencyHz: 14_074_000,
                              grid: "FN31")

        let adif = manager.buildSingleEntryADIF(entry)

        XCTAssertTrue(adif.contains("<CALL:5>K1ABC"),    "CALL field missing or wrong")
        XCTAssertTrue(adif.contains("<MODE:3>FT8"),      "MODE field missing or wrong")
        XCTAssertTrue(adif.contains("<BAND:3>20m"),      "BAND field missing")
        XCTAssertTrue(adif.contains("<RST_SENT:3>-10"),  "RST_SENT missing")
        XCTAssertTrue(adif.contains("<RST_RCVD:3>-12"),  "RST_RCVD missing")
        XCTAssertTrue(adif.contains("<GRIDSQUARE:4>FN31"), "GRIDSQUARE missing")
        XCTAssertTrue(adif.hasSuffix("<EOR>"),           "EOR marker missing or not last")
    }

    func testBuildADIF_DateAndTimeAreUTC() {
        // 2023-11-14 22:13:20 UTC
        let date  = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = makeEntry(date: date)

        let adif = manager.buildSingleEntryADIF(entry)

        XCTAssertTrue(adif.contains("<QSO_DATE:8>20231114"), "Date not UTC yyyyMMdd")
        XCTAssertTrue(adif.contains("<TIME_ON:6>221320"),    "Time not UTC HHmmss")
    }

    func testBuildADIF_FrequencyFormattedInMHz() {
        let entry = makeEntry(frequencyHz: 14_074_000)

        let adif = manager.buildSingleEntryADIF(entry)

        // 14_074_000 Hz → "14.074000" (9 chars) → <FREQ:9>14.074000
        XCTAssertTrue(adif.contains("<FREQ:9>14.074000"), "FREQ not in MHz or wrong format")
    }

    func testBuildADIF_OmitsFreqWhenNil() {
        let entry = makeEntry(frequencyHz: nil)

        let adif = manager.buildSingleEntryADIF(entry)

        XCTAssertFalse(adif.contains("<FREQ:"), "FREQ should be absent when frequencyHz is nil")
    }

    func testBuildADIF_IncludesStationCallsignWhenSet() {
        let entry = makeEntry(stationCallsign: "EA4IQL")

        let adif = manager.buildSingleEntryADIF(entry)

        XCTAssertTrue(adif.contains("<STATION_CALLSIGN:6>EA4IQL"), "STATION_CALLSIGN missing")
    }

    func testBuildADIF_OmitsStationCallsignWhenNil() {
        let entry = makeEntry(stationCallsign: nil)

        let adif = manager.buildSingleEntryADIF(entry)

        XCTAssertFalse(adif.contains("STATION_CALLSIGN"), "STATION_CALLSIGN should be absent when nil")
    }

    func testBuildADIF_OmitsGridWhenEmpty() {
        let entry = makeEntry(grid: "")

        let adif = manager.buildSingleEntryADIF(entry)

        XCTAssertFalse(adif.contains("GRIDSQUARE"), "GRIDSQUARE should be absent for empty grid")
    }

    // MARK: - syncNewQSO — QRZ

    func testSyncNewQSO_QRZDisabled_NoUpload() async throws {
        UserDefaults.standard.set(false, forKey: "qrzAutoUpload")
        mockQRZ.hasAPIKey = true

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockQRZ.uploadADIFCallCount, 0)
    }

    func testSyncNewQSO_QRZEnabled_NoAPIKey_NoUpload() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        mockQRZ.hasAPIKey = false

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockQRZ.uploadADIFCallCount, 0)
    }

    func testSyncNewQSO_QRZEnabled_WithAPIKey_Uploads() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        mockQRZ.hasAPIKey = true
        mockQRZ.uploadResult = QRZUploadResult(success: true)

        manager.syncNewQSO(makeEntry(callsign: "W1XYZ"))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockQRZ.uploadADIFCallCount, 1)
        XCTAssertTrue(mockQRZ.lastUploadedADIF?.contains("W1XYZ") == true)
    }

    func testSyncNewQSO_QRZSuccess_RemovesFromPending() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        mockQRZ.hasAPIKey = true
        mockQRZ.uploadResult = QRZUploadResult(success: true)

        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(manager.pendingQRZIDs.contains(entry.id.uuidString),
                       "Successful upload should remove entry from pending")
        XCTAssertEqual(manager.totalPendingCount, 0)
    }

    func testSyncNewQSO_QRZFailure_RemainsInPending() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        mockQRZ.hasAPIKey = true
        mockQRZ.uploadResult = QRZUploadResult(success: false, errorMessage: "Server error")

        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(manager.pendingQRZIDs.contains(entry.id.uuidString),
                      "Failed upload should keep entry in pending")
        XCTAssertEqual(manager.totalPendingCount, 1)
    }

    // MARK: - syncNewQSO — LoTW

    func testSyncNewQSO_LoTWDisabled_NoUpload() async throws {
        UserDefaults.standard.set(false, forKey: "lotwAutoUpload")
        mockLoTW.hasCertificate = true

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockLoTW.uploadADIFCallCount, 0)
    }

    func testSyncNewQSO_LoTWEnabled_NoCertificate_NoUpload() async throws {
        UserDefaults.standard.set(true, forKey: "lotwAutoUpload")
        mockLoTW.hasCertificate = false

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockLoTW.uploadADIFCallCount, 0)
    }

    func testSyncNewQSO_LoTWEnabled_WithCertificate_Uploads() async throws {
        UserDefaults.standard.set(true, forKey: "lotwAutoUpload")
        mockLoTW.hasCertificate = true
        mockLoTW.uploadResult = LoTWUploadResult(success: true)

        manager.syncNewQSO(makeEntry(callsign: "DL1XYZ"))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockLoTW.uploadADIFCallCount, 1)
        XCTAssertTrue(mockLoTW.lastUploadedADIF?.contains("DL1XYZ") == true)
    }

    func testSyncNewQSO_LoTWSuccess_RemovesFromPending() async throws {
        UserDefaults.standard.set(true, forKey: "lotwAutoUpload")
        mockLoTW.hasCertificate = true
        mockLoTW.uploadResult = LoTWUploadResult(success: true)

        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(manager.pendingLoTWIDs.contains(entry.id.uuidString),
                       "Successful LoTW upload should remove entry from pending")
    }

    func testSyncNewQSO_LoTWFailure_RemainsInPending() async throws {
        UserDefaults.standard.set(true, forKey: "lotwAutoUpload")
        mockLoTW.hasCertificate = true
        mockLoTW.uploadResult = LoTWUploadResult(success: false, errorMessage: "Certificate error")

        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(manager.pendingLoTWIDs.contains(entry.id.uuidString),
                      "Failed LoTW upload should keep entry in pending")
    }

    // MARK: - syncNewQSO — eQSL

    func testSyncNewQSO_EQSLDisabled_NoUpload() async throws {
        UserDefaults.standard.set(false, forKey: "eqslAutoUpload")
        mockEQSL.hasCredentials = true

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockEQSL.uploadADIFCallCount, 0)
    }

    func testSyncNewQSO_EQSLEnabled_NoCredentials_NoUpload() async throws {
        UserDefaults.standard.set(true, forKey: "eqslAutoUpload")
        mockEQSL.hasCredentials = false

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockEQSL.uploadADIFCallCount, 0)
    }

    func testSyncNewQSO_EQSLEnabled_WithCredentials_Uploads() async throws {
        UserDefaults.standard.set(true, forKey: "eqslAutoUpload")
        mockEQSL.hasCredentials = true
        mockEQSL.uploadResult = eQSLUploadResult(success: true)

        manager.syncNewQSO(makeEntry(callsign: "F4ABC"))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockEQSL.uploadADIFCallCount, 1)
        XCTAssertTrue(mockEQSL.lastUploadedADIF?.contains("F4ABC") == true)
    }

    func testSyncNewQSO_EQSLSuccess_RemovesFromPending() async throws {
        UserDefaults.standard.set(true, forKey: "eqslAutoUpload")
        mockEQSL.hasCredentials = true
        mockEQSL.uploadResult = eQSLUploadResult(success: true)

        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(manager.pendingEQSLIDs.contains(entry.id.uuidString),
                       "Successful eQSL upload should remove entry from pending")
    }

    func testSyncNewQSO_EQSLFailure_RemainsInPending() async throws {
        UserDefaults.standard.set(true, forKey: "eqslAutoUpload")
        mockEQSL.hasCredentials = true
        mockEQSL.uploadResult = eQSLUploadResult(success: false, errorMessage: "Auth error")

        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(manager.pendingEQSLIDs.contains(entry.id.uuidString),
                      "Failed eQSL upload should keep entry in pending")
    }

    // MARK: - totalPendingCount

    func testTotalPendingCount_StartsAtZero() {
        XCTAssertEqual(manager.totalPendingCount, 0)
    }

    func testTotalPendingCount_ReflectsBothServices() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        UserDefaults.standard.set(true, forKey: "lotwAutoUpload")
        mockQRZ.hasAPIKey      = true
        mockLoTW.hasCertificate = true
        // Both fail → both stay pending
        mockQRZ.uploadResult  = QRZUploadResult(success: false, errorMessage: "err")
        mockLoTW.uploadResult = LoTWUploadResult(success: false, errorMessage: "err")

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(manager.totalPendingCount, 2,
                       "One pending QRZ + one pending LoTW = totalPendingCount 2")
    }

    func testTotalPendingCount_ReflectsAllThreeServices() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        UserDefaults.standard.set(true, forKey: "lotwAutoUpload")
        UserDefaults.standard.set(true, forKey: "eqslAutoUpload")
        mockQRZ.hasAPIKey = true
        mockLoTW.hasCertificate = true
        mockEQSL.hasCredentials = true
        // All fail -> all remain pending
        mockQRZ.uploadResult = QRZUploadResult(success: false, errorMessage: "err")
        mockLoTW.uploadResult = LoTWUploadResult(success: false, errorMessage: "err")
        mockEQSL.uploadResult = eQSLUploadResult(success: false, errorMessage: "err")

        manager.syncNewQSO(makeEntry())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(manager.totalPendingCount, 3,
                       "One pending per service should produce totalPendingCount 3")
    }

    // MARK: - retryPendingUploads

    func testRetryPendingUploads_ClearsSuccessfulEntries() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        mockQRZ.hasAPIKey = true

        // First upload fails → entry stays in pending
        mockQRZ.uploadResult = QRZUploadResult(success: false, errorMessage: "fail")
        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(manager.pendingQRZIDs.count, 1)

        // Retry with success
        mockQRZ.uploadResult = QRZUploadResult(success: true)
        manager.retryPendingUploads([entry])
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(manager.pendingQRZIDs.count, 0,
                       "Successful retry should clear the entry from pending")
    }

    func testRetryPendingUploads_PrunesOrphanedIDs() async throws {
        UserDefaults.standard.set(true, forKey: "qrzAutoUpload")
        mockQRZ.hasAPIKey    = true
        mockQRZ.uploadResult = QRZUploadResult(success: false, errorMessage: "fail")

        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(manager.pendingQRZIDs.count, 1)

        // Retry with an empty list — the orphaned ID should be pruned
        manager.retryPendingUploads([])
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(manager.pendingQRZIDs.count, 0,
                       "Orphaned pending ID should be pruned when entry no longer exists")
    }

    func testRetryPendingUploads_EQSLClearsSuccessfulEntries() async throws {
        UserDefaults.standard.set(true, forKey: "eqslAutoUpload")
        mockEQSL.hasCredentials = true

        // First upload fails -> entry stays pending
        mockEQSL.uploadResult = eQSLUploadResult(success: false, errorMessage: "fail")
        let entry = makeEntry()
        manager.syncNewQSO(entry)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(manager.pendingEQSLIDs.count, 1)

        // Retry with success
        mockEQSL.uploadResult = eQSLUploadResult(success: true)
        manager.retryPendingUploads([entry])
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(manager.pendingEQSLIDs.count, 0,
                       "Successful eQSL retry should clear the entry from pending")
    }

    // MARK: - checkConfirmations

    func testCheckConfirmations_CallsFetchOnAllServices() async throws {
        UserDefaults.standard.set(3, forKey: "qrzConfirmationIntervalHours")

        manager.checkConfirmations()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockQRZ.fetchConfirmationsCallCount, 1)
        XCTAssertEqual(mockLoTW.fetchConfirmationsCallCount, 1)
        XCTAssertEqual(mockEQSL.fetchConfirmationsCallCount, 1)

        let now = Date()
        let expected = now.addingTimeInterval(-3 * 3600)
        let tolerance: TimeInterval = 10

        XCTAssertNotNil(mockQRZ.lastFetchDate)
        XCTAssertNotNil(mockLoTW.lastFetchDate)
        XCTAssertNotNil(mockEQSL.lastFetchDate)
        XCTAssertEqual(mockQRZ.lastFetchDate?.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970,
                       accuracy: tolerance)
        XCTAssertEqual(mockLoTW.lastFetchDate?.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970,
                       accuracy: tolerance)
        XCTAssertEqual(mockEQSL.lastFetchDate?.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970,
                       accuracy: tolerance)
    }

    // MARK: - Helper

    private func makeEntry(
        callsign:        String  = "K1ABC",
        date:            Date    = Date(),
        frequencyHz:     Double? = 14_074_000,
        stationCallsign: String? = nil,
        grid:            String  = "FN31"
    ) -> LogEntry {
        LogEntry(
            callsign:        callsign,
            grid:            grid,
            date:            date,
            frequencyHz:     frequencyHz,
            mode:            "FT8",
            band:            "20m",
            rstSent:         "-10",
            rstRcvd:         "-12",
            stationCallsign: stationCallsign,
            cqModifier:      nil,
            mySigInfo:       nil,
            country:         nil,
            flag:            nil
        )
    }
}
