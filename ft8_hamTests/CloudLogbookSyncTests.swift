//
//  CloudLogbookSyncTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 14/09/26.
//

import XCTest
@testable import ft8_ham

// MARK: - Mock

@MainActor
final class MockCloudLogbookSync: CloudLogbookSyncProtocol {
    var status: CloudSyncAccountStatus = .available
    var pullResult: Result<CloudPullResult, Error> = .success(CloudPullResult(upserted: [], deletedKeys: []))
    var pushError: Error?

    private(set) var pushed: [[CloudLogRecord]] = []
    private(set) var pullCount = 0
    private(set) var deleteCount = 0
    private(set) var resetTokenCount = 0

    func accountStatus() async -> CloudSyncAccountStatus { status }

    func push(_ records: [CloudLogRecord]) async throws {
        if let pushError { throw pushError }
        pushed.append(records)
    }

    func pullChanges() async throws -> CloudPullResult {
        pullCount += 1
        return try pullResult.get()
    }

    func deleteAllRemote() async throws { deleteCount += 1 }
    func resetChangeToken() { resetTokenCount += 1 }
}

// MARK: - Helpers

private func entry(
    _ call: String, band: String = "20m", mode: String = "FT8",
    minutesAgo: Int = 0, seconds: Int = 0
) -> LogEntry {
    // Minute-aligned base (2025-09-11 14:13:00 UTC) so `seconds` moves the
    // stamp within or across a minute exactly as the test intends.
    let date = Date(timeIntervalSince1970: 1_757_599_980 - TimeInterval(minutesAgo * 60) + TimeInterval(seconds))
    return LogEntry(
        callsign: call, grid: "JO62", date: date, frequencyHz: 14_074_000,
        mode: mode, band: band, rstSent: "-10", rstRcvd: "-12",
        stationCallsign: "EA4IQL", cqModifier: nil, mySigInfo: nil,
        country: "Germany", flag: "🇩🇪"
    )
}

// MARK: - Dedup key

final class LogEntryDedupKeyTests: XCTestCase {

    func test_dedupKey_isCallBandModeMinute() {
        let e = entry("dl1abc")
        XCTAssertEqual(e.dedupKey, "DL1ABC|20m|FT8|202509111413")
    }

    func test_dedupKey_ignoresSecondsWithinAMinute() {
        XCTAssertEqual(entry("K1ABC", seconds: 0).dedupKey, entry("K1ABC", seconds: 45).dedupKey)
    }

    func test_dedupKey_differsPerBandAndMode() {
        XCTAssertNotEqual(entry("K1ABC", band: "20m").dedupKey, entry("K1ABC", band: "40m").dedupKey)
        XCTAssertNotEqual(entry("K1ABC", mode: "FT8").dedupKey, entry("K1ABC", mode: "FT4").dedupKey)
    }

    func test_cloudRecord_roundTripsThroughLogEntry() {
        let original = entry("K1ABC")
        let restored = LogEntry(cloud: original.cloudRecord)

        XCTAssertEqual(restored.callsign, original.callsign)
        XCTAssertEqual(restored.grid, original.grid)
        XCTAssertEqual(restored.date, original.date)
        XCTAssertEqual(restored.band, original.band)
        XCTAssertEqual(restored.mode, original.mode)
        XCTAssertEqual(restored.rstSent, original.rstSent)
        XCTAssertEqual(restored.rstRcvd, original.rstRcvd)
        XCTAssertEqual(restored.country, original.country)
        XCTAssertEqual(restored.dedupKey, original.dedupKey)
        // A pulled entry gets its own local id (the sync queues are keyed by it).
        XCTAssertNotEqual(restored.id, original.id)
    }
}

// MARK: - Merge

final class CloudLogbookMergeTests: XCTestCase {

    func test_merge_addsUnknownEntriesSortedByDate() {
        let local = [entry("K1ABC", minutesAgo: 10)]
        let remote = [entry("DL1XYZ", minutesAgo: 5).cloudRecord, entry("G4ZZZ", minutesAgo: 20).cloudRecord]

        let merged = CloudLogbookSyncManager.merge(remote, into: local)

        XCTAssertEqual(merged.map(\.callsign), ["G4ZZZ", "K1ABC", "DL1XYZ"])
    }

    func test_merge_skipsRecordsAlreadyPresentByKey() {
        let local = [entry("K1ABC")]
        let merged = CloudLogbookSyncManager.merge([entry("K1ABC").cloudRecord], into: local)
        XCTAssertEqual(merged.count, 1)
    }

    func test_merge_skipsNearDuplicatesAcrossMinuteBoundary() {
        // Same QSO logged at 14:12:59 here and 14:13:00 on the other device:
        // different dedup keys, but the ±120 s rule collapses them.
        let local = [entry("K1ABC", seconds: -1)]
        let remote = [entry("K1ABC", seconds: 0).cloudRecord]
        XCTAssertNotEqual(local[0].dedupKey, remote[0].dedupKey)

        let merged = CloudLogbookSyncManager.merge(remote, into: local)
        XCTAssertEqual(merged.count, 1)
    }

    func test_merge_keepsSameCallOnAnotherBand() {
        let merged = CloudLogbookSyncManager.merge([entry("K1ABC", band: "40m").cloudRecord], into: [entry("K1ABC", band: "20m")])
        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_withNothingNew_returnsTheSameArray() {
        let local = [entry("K1ABC")]
        XCTAssertEqual(CloudLogbookSyncManager.merge([], into: local).count, 1)
        XCTAssertEqual(CloudLogbookSyncManager.merge([entry("K1ABC").cloudRecord], into: local).map(\.id), local.map(\.id))
    }
}

// MARK: - Manager

@MainActor
final class CloudLogbookSyncManagerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var service: MockCloudLogbookSync!
    private var viewModel: FT8ViewModel!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "CloudLogbookSyncManagerTests")!
        defaults.removePersistentDomain(forName: "CloudLogbookSyncManagerTests")
        service = MockCloudLogbookSync()
        viewModel = FT8ViewModel(audioManager: MockAudioManager(), engine: MockMessageDecoder())
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "CloudLogbookSyncManagerTests")
        viewModel = nil
        try await super.tearDown()
    }

    private func makeManager(gate: @escaping () -> Bool = { true }, enabled: Bool = true) -> CloudLogbookSyncManager {
        let m = CloudLogbookSyncManager(service: service, defaults: defaults, gate: gate)
        m.viewModel = viewModel
        m.isEnabled = enabled
        return m
    }

    func test_disabled_doesNotPush() async {
        let m = makeManager(enabled: false)
        let e = entry("K1ABC")
        viewModel.qsoList = [e]
        m.syncNewQSO(e)
        await m.pushPending()
        XCTAssertTrue(service.pushed.isEmpty)
        XCTAssertFalse(m.isActive)
    }

    func test_gateClosed_doesNotPush() async {
        let m = makeManager(gate: { false })
        let e = entry("K1ABC")
        viewModel.qsoList = [e]
        m.syncNewQSO(e)
        await m.pushPending()
        XCTAssertTrue(service.pushed.isEmpty)
        XCTAssertFalse(m.isActive)
    }

    func test_syncNewQSO_queuesAndPushes() async {
        let m = makeManager()
        let e = entry("K1ABC")
        viewModel.qsoList = [e]

        m.syncNewQSO(e)
        XCTAssertTrue(m.pendingKeys.contains(e.dedupKey))
        await m.pushPending()

        XCTAssertEqual(service.pushed.flatMap { $0 }.map(\.dedupKey), [e.dedupKey])
        XCTAssertTrue(m.pendingKeys.isEmpty)
        XCTAssertNil(m.lastError)
        XCTAssertNotNil(m.lastSyncDate)
    }

    func test_failedPush_keepsKeysQueuedAndPersisted() async {
        service.pushError = CloudLogbookSyncError.network("offline")
        let m = makeManager()
        let e = entry("K1ABC")
        viewModel.qsoList = [e]

        m.syncNewQSO(e)
        await m.pushPending()

        XCTAssertTrue(m.pendingKeys.contains(e.dedupKey))
        XCTAssertNotNil(m.lastError)
        XCTAssertEqual(Set(defaults.stringArray(forKey: CloudLogbookSyncManager.pendingKey) ?? []), [e.dedupKey])

        // A later retry, once the network is back, drains the queue.
        service.pushError = nil
        await m.pushPending()
        XCTAssertTrue(m.pendingKeys.isEmpty)
    }

    func test_pendingKeys_surviveRelaunch() async {
        service.pushError = CloudLogbookSyncError.network("offline")
        let e = entry("K1ABC")
        viewModel.qsoList = [e]
        let first = makeManager()
        first.syncNewQSO(e)
        await first.pushPending()

        let relaunched = makeManager()
        XCTAssertTrue(relaunched.pendingKeys.contains(e.dedupKey))
    }

    func test_pull_mergesIntoLogbook() async {
        let m = makeManager()
        viewModel.qsoList = [entry("K1ABC", minutesAgo: 10)]
        service.pullResult = .success(CloudPullResult(upserted: [entry("DL1XYZ").cloudRecord], deletedKeys: []))

        await m.pull()

        XCTAssertEqual(viewModel.qsoList.map(\.callsign), ["K1ABC", "DL1XYZ"])
        XCTAssertEqual(service.pullCount, 1)
    }

    func test_pull_ignoresRecordsWeAlreadyHave() async {
        let m = makeManager()
        let e = entry("K1ABC")
        viewModel.qsoList = [e]
        service.pullResult = .success(CloudPullResult(upserted: [e.cloudRecord], deletedKeys: []))

        await m.pull()
        XCTAssertEqual(viewModel.qsoList.count, 1)
    }

    func test_pull_failureIsReported() async {
        let m = makeManager()
        service.pullResult = .failure(CloudLogbookSyncError.server("boom"))
        await m.pull()
        XCTAssertNotNil(m.lastError)
    }

    func test_pushAll_sendsTheWholeLogbook() async {
        let m = makeManager()
        viewModel.qsoList = [entry("K1ABC"), entry("DL1XYZ", minutesAgo: 5)]
        await m.pushAll()
        XCTAssertEqual(service.pushed.first?.count, 2)
    }

    func test_deleteAllRemote_clearsQueue() async {
        service.pushError = CloudLogbookSyncError.network("offline")
        let m = makeManager()
        let e = entry("K1ABC")
        viewModel.qsoList = [e]
        m.syncNewQSO(e)
        await m.pushPending()
        XCTAssertFalse(m.pendingKeys.isEmpty)

        await m.deleteAllRemote()
        XCTAssertEqual(service.deleteCount, 1)
        XCTAssertTrue(m.pendingKeys.isEmpty)
    }
}
