//
//  ClockSyncTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

// MARK: - Mock

final class MockSNTPClient: SNTPQuerying, @unchecked Sendable {
    private let lock = NSLock()
    /// One entry per query, consumed in order; a `nil` entry throws.
    var results: [SNTPClient.Sample?]
    private(set) var queriedHosts: [String] = []

    init(results: [SNTPClient.Sample?]) { self.results = results }

    func query(host: String) async throws -> SNTPClient.Sample {
        lock.lock(); defer { lock.unlock() }
        queriedHosts.append(host)
        guard !results.isEmpty else { throw SNTPClient.SNTPError.timeout }
        guard let sample = results.removeFirst() else { throw SNTPClient.SNTPError.timeout }
        return sample
    }
}

private func sample(_ offset: TimeInterval, rtt: TimeInterval = 0.05) -> SNTPClient.Sample {
    SNTPClient.Sample(offset: offset, roundTrip: rtt, stratum: 2)
}

// MARK: - ClockSyncManager

@MainActor
final class ClockSyncManagerTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ClockSyncManagerTests")!
        defaults.removePersistentDomain(forName: "ClockSyncManagerTests")
        AppClock.shared.offset = 0
    }

    override func tearDown() {
        AppClock.shared.offset = 0
        defaults.removePersistentDomain(forName: "ClockSyncManagerTests")
        super.tearDown()
    }

    private func manager(_ client: MockSNTPClient, hosts: [String] = ["a", "b"]) -> ClockSyncManager {
        ClockSyncManager(client: client, hosts: hosts, defaults: defaults, samplesPerSync: 3)
    }

    func test_syncNow_appliesMedianOfThreeSamples() async {
        let client = MockSNTPClient(results: [sample(0.30), sample(0.34), sample(0.31)])
        let m = manager(client)

        await m.syncNow()

        XCTAssertEqual(m.offset, 0.31, accuracy: 1e-9)
        XCTAssertEqual(AppClock.shared.offset, 0.31, accuracy: 1e-9)
        XCTAssertNotNil(m.lastSyncDate)
        XCTAssertNil(m.lastError)
        XCTAssertEqual(client.queriedHosts, ["a", "a", "a"])
    }

    func test_syncNow_dropsSlowSamples() async {
        // 9.0 s came back over a 2 s round trip and is discarded.
        let client = MockSNTPClient(results: [sample(9.0, rtt: 2.0), sample(0.5), sample(0.5)])
        let m = manager(client)
        await m.syncNow()
        XCTAssertEqual(m.offset, 0.5, accuracy: 1e-9)
    }

    func test_syncNow_fallsBackToSecondHost() async {
        let client = MockSNTPClient(results: [nil, nil, nil, sample(1.5), sample(1.5), sample(1.5)])
        let m = manager(client)
        await m.syncNow()
        XCTAssertEqual(m.offset, 1.5, accuracy: 1e-9)
        XCTAssertEqual(client.queriedHosts, ["a", "a", "a", "b", "b", "b"])
        XCTAssertTrue(m.isWarning)
    }

    func test_syncNow_failureKeepsPreviousOffset() async {
        let m = manager(MockSNTPClient(results: []))
        m.apply(0.8)
        await m.syncNow()
        XCTAssertEqual(m.offset, 0.8, accuracy: 1e-9)
        XCTAssertEqual(AppClock.shared.offset, 0.8, accuracy: 1e-9)
        XCTAssertNotNil(m.lastError)
    }

    func test_apply_ignoresJitterBelowThreshold() {
        let m = manager(MockSNTPClient(results: []))
        m.apply(0.500)
        m.apply(0.505)
        XCTAssertEqual(m.offset, 0.500, accuracy: 1e-9)
        m.apply(0.6)
        XCTAssertEqual(m.offset, 0.6, accuracy: 1e-9)
    }

    func test_disabling_resetsOffsetAndSkipsSync() async {
        let m = manager(MockSNTPClient(results: [sample(2), sample(2), sample(2)]))
        m.apply(2)
        m.isEnabled = false
        XCTAssertEqual(m.offset, 0)
        XCTAssertEqual(AppClock.shared.offset, 0)
        await m.syncNow()
        XCTAssertEqual(m.offset, 0)
        XCTAssertFalse(m.isEnabled)
        XCTAssertEqual(defaults.bool(forKey: ClockSyncManager.enabledKey), false)
    }

    func test_isEnabled_defaultsToTrue() {
        XCTAssertTrue(manager(MockSNTPClient(results: [])).isEnabled)
    }
}

// MARK: - SlotManager on the corrected clock

final class SlotManagerClockOffsetTests: XCTestCase {

    override func tearDown() {
        AppClock.shared.offset = 0
        super.tearDown()
    }

    func test_getNextSlot_defaultReferenceFollowsAppClock() async {
        let manager = SlotManager()
        AppClock.shared.offset = 0
        let raw = await manager.getNextSlot(from: Date(), isFT4: false)

        // Push the corrected clock two full FT8 slots ahead.
        AppClock.shared.offset = 30
        let corrected = await manager.getNextSlot(isFT4: false)

        XCTAssertGreaterThanOrEqual(corrected.slotIndex - raw.slotIndex, 2)
        XCTAssertLessThanOrEqual(corrected.slotIndex - raw.slotIndex, 3)
    }

    func test_wait_usesCorrectedClockAfterResetAnchor() async throws {
        let manager = SlotManager()
        AppClock.shared.offset = 0
        try await manager.wait(until: AppClock.now().addingTimeInterval(0.05))

        // Offset jumps by 1 s; after resetAnchor a wait on the corrected clock
        // must return promptly instead of sleeping the extra second.
        AppClock.shared.offset = 1.0
        await manager.resetAnchor()
        let started = Date()
        try await manager.wait(until: AppClock.now().addingTimeInterval(0.05))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }
}
