//
//  HeardMeTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
import CoreLocation
@testable import ft8_ham

// MARK: - Mock

final class MockReceptionReportFetcher: ReceptionReportFetching, @unchecked Sendable {
    private let lock = NSLock()
    var result: Result<[ReceptionReport], Error>
    private(set) var calls: [(callsign: String, window: HeardMeWindow)] = []

    init(result: Result<[ReceptionReport], Error>) { self.result = result }

    func fetch(senderCallsign: String, window: HeardMeWindow) async throws -> [ReceptionReport] {
        lock.lock(); calls.append((senderCallsign, window)); lock.unlock()
        return try result.get()
    }
}

private func report(_ rx: String, locator: String, snr: Int? = -10, age: TimeInterval = 60, freq: Int64 = 14_074_000) -> ReceptionReport {
    ReceptionReport(
        receiverCallsign: rx, receiverLocator: locator, senderCallsign: "EA4IQL",
        frequencyHz: freq, snr: snr, mode: "FT8", flowStart: Date().addingTimeInterval(-age)
    )
}

// MARK: - XML parser

final class ReceptionReportXMLParserTests: XCTestCase {

    private let fixture = """
    <?xml version="1.0"?>
    <receptionReports currentSeconds="1757600000">
      <activeReceiver callsign="DL1ABC" locator="JO62QM" mode="FT8"/>
      <receptionReport receiverCallsign="DL1ABC" receiverLocator="JO62qm" senderCallsign="EA4IQL" senderLocator="IN80" frequency="14074123" flowStartSeconds="1757599700" mode="FT8" sNR="-12"/>
      <receptionReport receiverCallsign="g4xyz" receiverLocator="IO91" senderCallsign="EA4IQL" frequency="14074123" flowStartSeconds="1757599800" mode="FT8"/>
      <receptionReport receiverCallsign="BAD" receiverLocator="ZZ" senderCallsign="EA4IQL" frequency="1" flowStartSeconds="1" mode="FT8" sNR="0"/>
      <receptionReport receiverCallsign="NOTIME" receiverLocator="JN58" senderCallsign="EA4IQL" mode="FT8"/>
    </receptionReports>
    """

    func test_parse_readsReportsAndSkipsMalformedOnes() throws {
        let reports = try ReceptionReportXMLParser.parse(Data(fixture.utf8))
        XCTAssertEqual(reports.map(\.receiverCallsign), ["DL1ABC", "G4XYZ"])

        let first = reports[0]
        XCTAssertEqual(first.receiverLocator, "JO62QM")
        XCTAssertEqual(first.senderCallsign, "EA4IQL")
        XCTAssertEqual(first.frequencyHz, 14_074_123)
        XCTAssertEqual(first.snr, -12)
        XCTAssertEqual(first.mode, "FT8")
        XCTAssertEqual(first.flowStart.timeIntervalSince1970, 1_757_599_700)

        XCTAssertNil(reports[1].snr, "missing sNR must not drop the report")
    }

    func test_parse_throwsOnBrokenXML() {
        XCTAssertThrowsError(try ReceptionReportXMLParser.parse(Data("<receptionReports><receptionReport".utf8)))
    }

    func test_makeURL_includesEtiquetteParameters() throws {
        let url = try XCTUnwrap(PSKReporterRetrieveClient.makeURL(senderCallsign: "ea4iql", window: .fifteenMinutes))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "retrieve.pskreporter.info")
        XCTAssertEqual(dict["senderCallsign"], "EA4IQL")
        XCTAssertEqual(dict["flowStartSeconds"], "-900")
        XCTAssertEqual(dict["rronly"], "1")
        XCTAssertEqual(dict["appcontact"], PSKReporterRetrieveClient.appContact)
    }
}

// MARK: - Grid centre

final class MaidenheadGridCenterTests: XCTestCase {

    func test_center_of4CharLocator() throws {
        let c = try XCTUnwrap(MaidenheadGrid.center(for: "JN58"))
        XCTAssertEqual(c.latitude, 48.5, accuracy: 1e-9)
        XCTAssertEqual(c.longitude, 11.0, accuracy: 1e-9)
    }

    func test_center_of6CharLocatorIsInsideItsSquare() throws {
        let c = try XCTUnwrap(MaidenheadGrid.center(for: "IN80dj"))
        XCTAssertEqual(MaidenheadGrid.locator(latitude: c.latitude, longitude: c.longitude, precision: 6), "IN80dj")
    }

    func test_center_rejectsGarbage() {
        XCTAssertNil(MaidenheadGrid.center(for: "ZZ"))
        XCTAssertNil(MaidenheadGrid.center(for: ""))
    }
}

// MARK: - Store

@MainActor
final class HeardMeStoreTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "HeardMeStoreTests")!
        defaults.removePersistentDomain(forName: "HeardMeStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "HeardMeStoreTests")
        super.tearDown()
    }

    private func store(_ fetcher: MockReceptionReportFetcher, minInterval: TimeInterval = 300) -> HeardMeStore {
        HeardMeStore(fetcher: fetcher, defaults: defaults, minInterval: minInterval)
    }

    func test_group_aggregatesByReceiverSortedByDistance() {
        let reports = [
            report("DL1ABC", locator: "JO62", snr: -15, age: 600),
            report("DL1ABC", locator: "JO62", snr: -3, age: 60),      // best SNR, latest
            report("G4XYZ", locator: "IO91", snr: -20, age: 120),
            report("EA1AAA", locator: "IN73", snr: nil, age: 30),
        ]
        let stations = HeardMeStore.group(reports, myLocator: "IN80")

        XCTAssertEqual(stations.map(\.callsign), ["EA1AAA", "G4XYZ", "DL1ABC"], "nearest first")
        let dl = stations[2]
        XCTAssertEqual(dl.bestSNR, -3)
        XCTAssertEqual(dl.reportCount, 2)
        XCTAssertEqual(dl.lastHeard.timeIntervalSinceNow, -60, accuracy: 2)
        XCTAssertNil(stations[0].bestSNR)

        // Madrid (IN80) → Berlin (JO62) is roughly 1 850 km.
        let km = try! XCTUnwrap(dl.distanceKm)
        XCTAssertEqual(km, 1850, accuracy: 100)
    }

    func test_group_withoutMyLocator_hasNoDistanceButKeepsStations() {
        let stations = HeardMeStore.group([report("DL1ABC", locator: "JO62")], myLocator: "")
        XCTAssertEqual(stations.count, 1)
        XCTAssertNil(stations[0].distanceKm)
    }

    func test_refresh_fetchesGroupsAndArmsRateLimit() async {
        let fetcher = MockReceptionReportFetcher(result: .success([report("DL1ABC", locator: "JO62")]))
        let s = store(fetcher)

        await s.refresh(callsign: "ea4iql", myLocator: "IN80")

        XCTAssertEqual(s.stations.map(\.callsign), ["DL1ABC"])
        XCTAssertEqual(fetcher.calls.first?.callsign, "EA4IQL")
        XCTAssertNil(s.lastError)
        XCTAssertFalse(s.canFetch)
        XCTAssertEqual(s.secondsUntilNextFetch, 300, accuracy: 2)
        XCTAssertNotNil(defaults.object(forKey: HeardMeStore.lastFetchKey))
    }

    func test_refresh_insideRateLimit_isRefused() async {
        let fetcher = MockReceptionReportFetcher(result: .success([]))
        let s = store(fetcher)
        await s.refresh(callsign: "EA4IQL", myLocator: "IN80")
        await s.refresh(callsign: "EA4IQL", myLocator: "IN80")
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertNotNil(s.lastError)
        s.refreshIfAllowed(callsign: "EA4IQL", myLocator: "IN80")
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    func test_rateLimit_survivesRelaunch() async {
        let fetcher = MockReceptionReportFetcher(result: .success([]))
        await store(fetcher).refresh(callsign: "EA4IQL", myLocator: "IN80")
        let relaunched = store(fetcher)
        XCTAssertFalse(relaunched.canFetch)
    }

    func test_refresh_emptyCallsign_doesNotQuery() async {
        let fetcher = MockReceptionReportFetcher(result: .success([]))
        let s = store(fetcher)
        await s.refresh(callsign: "  ", myLocator: "IN80")
        XCTAssertTrue(fetcher.calls.isEmpty)
        XCTAssertNotNil(s.lastError)
        XCTAssertTrue(s.canFetch)
    }

    func test_rateLimited_doublesBackoffUpToCap() async {
        let fetcher = MockReceptionReportFetcher(result: .failure(PSKReporterRetrieveError.rateLimited))
        let s = store(fetcher, minInterval: 1)
        await s.refresh(callsign: "EA4IQL", myLocator: "IN80")
        XCTAssertEqual(s.secondsUntilNextFetch, 2, accuracy: 0.5)
        XCTAssertNotNil(s.lastError)
    }

    func test_window_filtersClientSideWithoutRefetch() async {
        let fetcher = MockReceptionReportFetcher(result: .success([
            report("OLD", locator: "JO62", age: 3600),
            report("NEW", locator: "IO91", age: 60),
        ]))
        let s = store(fetcher)
        s.window = .twentyFourHours
        await s.refresh(callsign: "EA4IQL", myLocator: "IN80")
        XCTAssertEqual(Set(s.stations.map(\.callsign)), ["OLD", "NEW"])

        s.window = .fifteenMinutes
        XCTAssertEqual(s.stations.map(\.callsign), ["NEW"])
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertEqual(defaults.integer(forKey: HeardMeStore.windowKey), HeardMeWindow.fifteenMinutes.rawValue)
    }

    func test_format_isMinutesAndSeconds() {
        XCTAssertEqual(HeardMeStore.format(0), "0:00")
        XCTAssertEqual(HeardMeStore.format(299.2), "5:00")
        XCTAssertEqual(HeardMeStore.format(61), "1:01")
    }
}
