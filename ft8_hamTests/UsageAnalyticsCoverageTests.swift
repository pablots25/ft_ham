//
//  UsageAnalyticsCoverageTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 14/11/26.
//

import XCTest
@testable import ft8_ham

/// The usage events added to cover free text, bands, the logbook, the map,
/// confirmations, iCloud, presence, the RX filter and tutorials.
@MainActor
final class UsageAnalyticsCoverageTests: XCTestCase {

    private var logger: MockAnalyticsLogger!
    private var optedIn = true
    private var analytics: UsageAnalytics!

    private let suiteName = "UsageAnalyticsCoverageTests"

    override func setUp() {
        super.setUp()
        logger = MockAnalyticsLogger()
        UserDefaults().removePersistentDomain(forName: suiteName)
        optedIn = true
        analytics = UsageAnalytics(
            logger: logger,
            isOptedIn: { [unowned self] in self.optedIn },
            defaults: UserDefaults(suiteName: suiteName)!
        )
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        analytics = nil
        logger = nil
        super.tearDown()
    }

    private var actions: [MockAnalyticsLogger.Event] {
        logger.events(named: UsageAnalyticsEvent.Name.featureAction)
    }

    // MARK: - feature_action with a count

    func test_featureAction_withCount_sendsCount() {
        let parameters = UsageAnalyticsEvent.featureAction(.qrzLogbook, .confirmed, count: 12).parameters
        XCTAssertEqual(parameters[AnalyticsParam.feature] as? String, "qrz_logbook_sync")
        XCTAssertEqual(parameters[AnalyticsParam.action] as? String, "confirmed")
        XCTAssertEqual((parameters[AnalyticsParam.count] as? NSNumber)?.intValue, 12)
        XCTAssertNil(parameters[AnalyticsParam.source])
    }

    func test_featureAction_withoutCount_hasNoCount() {
        let parameters = UsageAnalyticsEvent.featureAction(.freeTextTX, .started).parameters
        XCTAssertNil(parameters[AnalyticsParam.count])
        XCTAssertEqual(parameters[AnalyticsParam.feature] as? String, "free_text_tx")
    }

    func test_recordAction_passesSourceAndCount() {
        analytics.recordAction(.logbook, .deleted, count: 3)
        analytics.recordAction(.rxFilter, .selected, source: RXFilterMode.mineAndCQ.analyticsValue)

        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].string(AnalyticsParam.feature), "logbook")
        XCTAssertEqual(actions[0].int(AnalyticsParam.count), 3)
        XCTAssertEqual(actions[1].string(AnalyticsParam.source), "mine_and_cq")
    }

    // MARK: - Once per session, per source

    func test_oncePerSession_isPerSource() {
        analytics.recordActionOncePerSession(.logbook, .searched)
        analytics.recordActionOncePerSession(.logbook, .searched)
        analytics.recordActionOncePerSession(.tutorials, .reset, source: "a")
        analytics.recordActionOncePerSession(.tutorials, .reset, source: "b")
        XCTAssertEqual(actions.count, 3)

        analytics.flush()
        analytics.recordActionOncePerSession(.logbook, .searched)
        XCTAssertEqual(actions.count, 4, "A new session sends it again")
    }

    // MARK: - Band in use

    func test_bandInUse_sentOncePerBandEachSession() {
        analytics.recordBandInUse(.band20m)
        analytics.recordBandInUse(.band20m)
        analytics.recordBandInUse(.band40m)

        XCTAssertEqual(actions.map { $0.string(AnalyticsParam.source) }, ["20m", "40m"])
        XCTAssertTrue(actions.allSatisfy { $0.string(AnalyticsParam.feature) == "band" })
        XCTAssertTrue(actions.allSatisfy { $0.string(AnalyticsParam.action) == "used" })

        analytics.flush()
        analytics.recordBandInUse(.band20m)
        XCTAssertEqual(actions.count, 3)
    }

    func test_bandInUse_skipsCustomAndUnknown() {
        analytics.recordBandInUse(.custom)
        analytics.recordBandInUse(.unknown)
        XCTAssertTrue(logger.events.isEmpty)
    }

    func test_bandInUse_respectsOptOut() {
        optedIn = false
        analytics.recordBandInUse(.band20m)
        optedIn = true
        analytics.recordBandInUse(.band20m)
        XCTAssertEqual(actions.count, 1, "Dropping while opted out must not use up the session slot")
    }

    // MARK: - Presence

    func test_presence_sendsTheMostSeenOnFlush() {
        analytics.presenceStationsSeen(4)
        analytics.presenceStationsSeen(9)
        analytics.presenceStationsSeen(2)
        XCTAssertTrue(logger.events.isEmpty, "Nothing is sent per fetch")

        analytics.flush()
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].string(AnalyticsParam.feature), "presence")
        XCTAssertEqual(actions[0].string(AnalyticsParam.action), "seen")
        XCTAssertEqual(actions[0].int(AnalyticsParam.count), 9)

        analytics.flush()
        XCTAssertEqual(actions.count, 1, "The counter starts again after a flush")
    }

    func test_presence_noStations_sendsNothing() {
        analytics.presenceStationsSeen(0)
        analytics.flush()
        XCTAssertTrue(actions.isEmpty)
    }

    func test_presence_respectsOptOut() {
        optedIn = false
        analytics.presenceStationsSeen(5)
        analytics.flush()
        XCTAssertTrue(logger.events.isEmpty)
    }

    // MARK: - Confirmation counts

    func test_confirmationCounter_readsQRZNumber() {
        XCTAssertEqual(ConfirmationCounter.count(in: "7"), 7)
        XCTAssertEqual(ConfirmationCounter.count(in: " 3\n"), 3)
        XCTAssertEqual(ConfirmationCounter.count(in: "-2"), 0)
    }

    func test_confirmationCounter_countsADIFRecords() {
        let adif = """
        ARRL Logbook of the World Status Report
        <eoh>
        <CALL:5>EA4XX<QSL_RCVD:1>Y<eor>
        <CALL:5>K1ABC<QSL_RCVD:1>Y<EOR>
        """
        XCTAssertEqual(ConfirmationCounter.count(in: adif), 2)
    }

    func test_confirmationCounter_emptyOrMissing_isZero() {
        XCTAssertEqual(ConfirmationCounter.count(in: nil), 0)
        XCTAssertEqual(ConfirmationCounter.count(in: ""), 0)
        XCTAssertEqual(ConfirmationCounter.count(in: "<eoh>"), 0)
    }

    // MARK: - Vocabulary

    func test_rxFilterValues_areDistinctAndSnakeCase() {
        let values = RXFilterMode.allCases.map(\.analyticsValue)
        XCTAssertEqual(Set(values).count, values.count)
        for value in values {
            XCTAssertNotNil(value.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression), value)
        }
    }

    func test_bandSources_fitFirebaseLimits() {
        for band in FT8Message.Band.allCases where band != .custom && band != .unknown {
            XCTAssertLessThanOrEqual(band.rawValue.count, 100, band.rawValue)
        }
    }

    func test_settingsScreenNames_fitFirebaseRules() {
        let names: [AnalyticsScreen] = [
            .settingsStation, .settingsRadio, .settingsAudio, .settingsAutomation,
            .settingsDisplay, .settingsWaterfall, .settingsReporting, .settingsCATControl,
            .settingsBandHopping, .settingsQRZ, .settingsLoTW, .settingsEQSL,
            .settingsICloudSync, .settingsTutorials, .settingsDebug, .settingsLegal
        ]
        XCTAssertEqual(Set(names.map(\.rawValue)).count, names.count)
        for name in names {
            XCTAssertTrue(name.rawValue.hasPrefix("settings_"), name.rawValue)
            XCTAssertLessThanOrEqual(name.rawValue.count, 100)
        }
    }
}
