//
//  QSOConsistencyTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 25/09/26.
//
//  The unified worked check, per-service confirmation intervals and the
//  localized QSO status text. Offline, no audio.
//

import XCTest
@testable import ft8_ham

// MARK: - isWorked

@MainActor
final class WorkedCheckTests: XCTestCase {

    private var viewModel: FT8ViewModel!
    private var savedDefaults: [String: Any?] = [:]
    private let touchedKeys = ["band", "isFT4", "customDialFrequencyHz", "highlightNewCallsigns"]

    override func setUp() async throws {
        try await super.setUp()
        for key in touchedKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        viewModel = FT8ViewModel(
            audioManager: MockAudioManager(),
            engine: MockMessageDecoder(),
            logbookManager: MockLogbookManager()
        )
        viewModel.selectedBand = .band20m
        viewModel.isFT4 = false
        viewModel.qsoList = [logEntry(callsign: "EA2ABC", band: .band20m, isFT4: false)]
    }

    override func tearDown() async throws {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        savedDefaults = [:]
        viewModel = nil
        try await super.tearDown()
    }

    private func logEntry(callsign: String, band: FT8Message.Band, isFT4: Bool) -> LogEntry {
        viewModel.qsoManager.createLogEntry(
            dxCallsign: callsign,
            dxLocator: "IN83",
            qsoDate: .now,
            band: band,
            isFT4: isFT4,
            rstSent: -10,
            rstRcvd: -8
        )
    }

    func testIsWorked_isCaseInsensitiveAndTrimsWhitespace() {
        XCTAssertTrue(viewModel.isWorked("EA2ABC"))
        XCTAssertTrue(viewModel.isWorked("ea2abc"))
        XCTAssertTrue(viewModel.isWorked("  Ea2AbC \n"))
    }

    func testIsWorked_emptyOrNilIsNeverWorked() {
        XCTAssertFalse(viewModel.isWorked(nil))
        XCTAssertFalse(viewModel.isWorked(""))
        XCTAssertFalse(viewModel.isWorked("   ", scope: .anyBand))
    }

    func testIsWorked_defaultsToCurrentBandAndMode() {
        XCTAssertTrue(viewModel.isWorked("EA2ABC"), "Worked on 20m FT8, currently on 20m FT8")

        viewModel.selectedBand = .band40m
        XCTAssertFalse(viewModel.isWorked("EA2ABC"), "Not worked on 40m")
        XCTAssertTrue(viewModel.isWorked("EA2ABC", scope: .anyBand))

        viewModel.selectedBand = .band20m
        viewModel.isFT4 = true
        XCTAssertFalse(viewModel.isWorked("EA2ABC"), "Not worked in FT4")
    }

    func testIsWorked_usesEffectiveBandForCustomFrequency() {
        viewModel.selectedBand = .custom
        viewModel.customDialFrequencyHz = 14_074_000
        XCTAssertEqual(viewModel.effectiveBand, .band20m)

        XCTAssertTrue(viewModel.isWorked("ea2abc"),
                      "A custom dial frequency on 20m must match 20m log entries")
    }

    func testIsWorked_explicitBandAndMode() {
        XCTAssertTrue(viewModel.isWorked("EA2ABC", scope: .bandAndMode(.band20m, mode: "ft8")))
        XCTAssertFalse(viewModel.isWorked("EA2ABC", scope: .bandAndMode(.band20m, mode: "FT4")))
        XCTAssertFalse(viewModel.isWorked("EA2ABC", scope: .bandAndMode(.band15m, mode: "FT8")))
    }

    func testIsWorked_unknownCallsign() {
        XCTAssertFalse(viewModel.isWorked("DL1XYZ"))
        XCTAssertFalse(viewModel.isWorked("DL1XYZ", scope: .anyBand))
    }

    func testWrappers_agreeWithIsWorked() {
        viewModel.selectedBand = .band40m
        XCTAssertFalse(viewModel.isNewCallsign("ea2abc"), "Worked on any band means not new")
        XCTAssertTrue(viewModel.isNewCallsign("DL1XYZ"))

        viewModel.highlightNewCallsigns = true
        let workedCQ = FT8Message(text: "CQ EA2ABC IN83", mode: .ft8, measuredSNR: 5,
                                  frequency: 1200, band: .band40m)
        XCTAssertFalse(viewModel.isNewCQCallsign(workedCQ))
    }
}

// MARK: - Confirmation intervals

@MainActor
final class ConfirmationIntervalTests: XCTestCase {

    private var mockQRZ: MockQRZService!
    private var mockLoTW: MockLoTWService!
    private var mockEQSL: MockEQSLService!
    private var manager: LogSyncManager!
    private let keys = ["qrzConfirmationIntervalHours", "lotwConfirmationIntervalHours"]
    private var savedDefaults: [String: Any?] = [:]

    override func setUp() async throws {
        try await super.setUp()
        for key in keys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        mockQRZ = MockQRZService()
        mockLoTW = MockLoTWService()
        mockEQSL = MockEQSLService()
        manager = LogSyncManager(qrzService: mockQRZ, lotwService: mockLoTW, eqslService: mockEQSL)
    }

    override func tearDown() async throws {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        savedDefaults = [:]
        manager = nil
        mockQRZ = nil
        mockLoTW = nil
        mockEQSL = nil
        try await super.tearDown()
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "ConfirmationIntervalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testInterval_defaultsToSixHoursWhenUnset() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(LogSyncManager.confirmationIntervalHours(for: .qrz, defaults: defaults), 6)
        XCTAssertEqual(LogSyncManager.confirmationIntervalHours(for: .lotw, defaults: defaults), 6)
    }

    func testInterval_eachServiceReadsItsOwnKey() {
        let defaults = isolatedDefaults()
        defaults.set(2, forKey: "qrzConfirmationIntervalHours")
        defaults.set(24, forKey: "lotwConfirmationIntervalHours")

        XCTAssertEqual(LogSyncManager.confirmationIntervalHours(for: .qrz, defaults: defaults), 2)
        XCTAssertEqual(LogSyncManager.confirmationIntervalHours(for: .lotw, defaults: defaults), 24)
    }

    func testInterval_lotwUnsetDoesNotFollowQRZ() {
        let defaults = isolatedDefaults()
        defaults.set(2, forKey: "qrzConfirmationIntervalHours")

        XCTAssertEqual(LogSyncManager.confirmationIntervalHours(for: .lotw, defaults: defaults), 6)
    }

    func testCheckConfirmations_lotwUsesItsOwnLookBackWindow() async throws {
        UserDefaults.standard.set(3, forKey: "qrzConfirmationIntervalHours")
        UserDefaults.standard.set(12, forKey: "lotwConfirmationIntervalHours")

        manager.checkConfirmations()
        try await Task.sleep(for: .milliseconds(100))

        let now = Date().timeIntervalSince1970
        let tolerance: TimeInterval = 10
        XCTAssertEqual(mockQRZ.lastFetchDate?.timeIntervalSince1970 ?? 0, now - 3 * 3600, accuracy: tolerance)
        XCTAssertEqual(mockEQSL.lastFetchDate?.timeIntervalSince1970 ?? 0, now - 3 * 3600, accuracy: tolerance)
        XCTAssertEqual(mockLoTW.lastFetchDate?.timeIntervalSince1970 ?? 0, now - 12 * 3600, accuracy: tolerance)
    }
}

// MARK: - Localized QSO status

final class QSOStateLocalizedTests: XCTestCase {

    private let allStates: [QSOState] = [
        .idle, .callingCQ,
        .sendingGrid(dxCallsign: "K1ABC"),
        .sendingReport(dxCallsign: "K1ABC"), .listeningReport(dxCallsign: "K1ABC"),
        .sendingRReport(dxCallsign: "K1ABC"), .listeningRReport(dxCallsign: "K1ABC"),
        .sendingRRR(dxCallsign: "K1ABC"), .listeningRRR(dxCallsign: "K1ABC"),
        .sending73(dxCallsign: "K1ABC"),
        .completed(dxCallsign: "K1ABC"), .timeout(dxCallsign: "K1ABC")
    ]

    func testLocalizedStatus_isNeverEmpty() {
        for state in allStates {
            XCTAssertFalse(state.localizedStatus.isEmpty, "\(state)")
        }
    }

    func testLocalizedStatus_interpolatesCallsign() {
        for state in allStates where state.lockedCallsign != nil {
            XCTAssertTrue(state.localizedStatus.contains("K1ABC"), "\(state): \(state.localizedStatus)")
            XCTAssertFalse(state.localizedStatus.contains("%@"), "\(state): format not applied")
        }
    }

    func testLocalizedStatus_statesWithoutPeerDoNotMentionOne() {
        XCTAssertFalse(QSOState.idle.localizedStatus.contains("K1ABC"))
        XCTAssertFalse(QSOState.callingCQ.localizedStatus.contains("K1ABC"))
    }

    func testLocalizedStatus_emptyCallsignUsesUnknownPeer() {
        let status = QSOState.sendingGrid(dxCallsign: "").localizedStatus
        XCTAssertFalse(status.isEmpty)
        XCTAssertFalse(status.contains("%@"))
        XCTAssertNotEqual(status, QSOState.sendingGrid(dxCallsign: "K1ABC").localizedStatus)
    }

    func testLocalizedStatus_isNotTheLoggerDescription() {
        // `description` stays English and callsign-free for the logger.
        XCTAssertFalse(QSOState.sendingGrid(dxCallsign: "K1ABC").description.contains("K1ABC"))
    }
}
