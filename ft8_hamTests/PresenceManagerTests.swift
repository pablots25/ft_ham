//
//  PresenceManagerTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 14/09/26.
//

import XCTest
@testable import ft8_ham

// MARK: - Mock

@MainActor
final class MockPresenceService: PresenceServiceProtocol {
    struct Upsert: Equatable {
        let callsign: String, grid4: String, band: String, mode: String
    }

    var online: [PresenceStation] = []
    var upsertError: Error?
    var fetchError: Error?

    private(set) var upserts: [Upsert] = []
    private(set) var fetchCount = 0
    private(set) var removeCount = 0

    func upsert(callsign: String, grid4: String, band: String, mode: String) async throws {
        if let upsertError { throw upsertError }
        upserts.append(Upsert(callsign: callsign, grid4: grid4, band: band, mode: mode))
    }

    func fetchOnline(since date: Date) async throws -> [PresenceStation] {
        fetchCount += 1
        if let fetchError { throw fetchError }
        return online
    }

    func removeMine() async throws { removeCount += 1 }
}

private func station(_ call: String, grid: String = "JO62", minutesAgo: Double = 1) -> PresenceStation {
    PresenceStation(
        callsign: call, grid: grid, band: "20m", mode: "FT8",
        lastSeen: Date().addingTimeInterval(-minutesAgo * 60)
    )
}

// MARK: - Tests

@MainActor
final class PresenceManagerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var service: MockPresenceService!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "PresenceManagerTests")!
        defaults.removePersistentDomain(forName: "PresenceManagerTests")
        service = MockPresenceService()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "PresenceManagerTests")
        try await super.tearDown()
    }

    private func makeManager(gate: @escaping () -> Bool = { true }, optIn: Bool = true) -> PresenceManager {
        let m = PresenceManager(
            service: service, defaults: defaults, gate: gate,
            upsertInterval: 3600, fetchInterval: 3600, staleAfter: 900
        )
        m.optIn = optIn
        return m
    }

    /// The publish/fetch loops are Tasks; give them a couple of hops to run.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // MARK: Publishing

    func test_optInOff_neverPublishes() async {
        let m = makeManager(optIn: false)
        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN80DJ", band: "20m", mode: "FT8")
        await settle()
        XCTAssertTrue(service.upserts.isEmpty)
        XCTAssertFalse(m.isActive)
    }

    func test_gateClosed_neverPublishes() async {
        let m = makeManager(gate: { false })
        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN80DJ", band: "20m", mode: "FT8")
        await settle()
        XCTAssertTrue(service.upserts.isEmpty)
    }

    func test_sequencerStart_publishesFourCharacterGridOnly() async {
        let m = makeManager()
        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN80DJ", band: "20m", mode: "FT8")
        await settle()

        XCTAssertEqual(service.upserts.first, .init(callsign: "EA4IQL", grid4: "IN80", band: "20m", mode: "FT8"))
        XCTAssertNil(m.lastError)
    }

    func test_incompleteStation_doesNotPublish() async {
        let m = makeManager()
        m.sequencerDidStart(callsign: "", grid: "IN80", band: "20m", mode: "FT8")
        await settle()
        XCTAssertTrue(service.upserts.isEmpty)

        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN", band: "20m", mode: "FT8")
        await settle()
        XCTAssertTrue(service.upserts.isEmpty)
    }

    func test_sequencerStop_stopsPublishing() async {
        let m = makeManager()
        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN80", band: "20m", mode: "FT8")
        await settle()
        let published = service.upserts.count

        m.sequencerDidStop()
        m.contextDidChange(band: "40m", mode: "FT8", grid: "IN80")
        await settle()
        XCTAssertEqual(service.upserts.count, published, "no publishing once off the air")
    }

    func test_publishFailure_isSurfaced() async {
        service.upsertError = PresenceError.network("offline")
        let m = makeManager()
        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN80", band: "20m", mode: "FT8")
        await settle()
        XCTAssertNotNil(m.lastError)
    }

    // MARK: Fetching

    func test_fetch_onlyWhileMapIsVisible() async {
        let m = makeManager()
        service.online = [station("DL1ABC")]

        m.mapDidAppear()
        await settle()
        XCTAssertEqual(service.fetchCount, 1)
        XCTAssertEqual(m.stations.map(\.callsign), ["DL1ABC"])

        m.mapDidDisappear()
        let count = service.fetchCount
        await settle()
        XCTAssertEqual(service.fetchCount, count)
    }

    func test_fetch_doesNothingWhenInactive() async {
        let m = makeManager(optIn: false)
        m.mapDidAppear()
        await settle()
        XCTAssertEqual(service.fetchCount, 0)
    }

    // MARK: Visible stations

    func test_visibleStations_dropStaleOnesAndOurselves() async {
        let m = makeManager()
        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN80", band: "20m", mode: "FT8")
        service.online = [
            station("DL1ABC", minutesAgo: 2),
            station("G4XYZ", minutesAgo: 30),      // older than the 15 min window
            station("ea4iql", minutesAgo: 1),      // ourselves
        ]
        m.mapDidAppear()
        await settle()

        XCTAssertEqual(m.visibleStations.map(\.callsign), ["DL1ABC"])
    }

    // MARK: Opting out

    func test_optOut_withdrawsTheRecordAndClearsTheMap() async {
        let m = makeManager()
        service.online = [station("DL1ABC")]
        m.sequencerDidStart(callsign: "EA4IQL", grid: "IN80", band: "20m", mode: "FT8")
        m.mapDidAppear()
        await settle()
        XCTAssertFalse(m.stations.isEmpty)

        m.optIn = false
        await settle()

        XCTAssertEqual(service.removeCount, 1)
        XCTAssertTrue(m.stations.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: PresenceManager.optInKey))
    }

    func test_optIn_defaultsToOff() {
        let m = PresenceManager(service: service, defaults: defaults, gate: { true })
        XCTAssertFalse(m.optIn)
        XCTAssertFalse(m.isActive)
    }
}
