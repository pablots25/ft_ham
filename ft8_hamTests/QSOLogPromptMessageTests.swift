//
//  QSOLogPromptMessageTests.swift
//  ft_ham
//
//  The "Log incomplete QSO?" alert used to say "both signal reports were
//  exchanged" for every unconfirmed QSO, including a manual "Log QSO" press
//  before the other station sent its report (Crashlytics ft8_ham.QSO -1,
//  1.3.0 (23), RST_RCVD invalid). These tests pin the wording to the reports
//  the entry actually holds.
//

import XCTest
@testable import ft8_ham

@MainActor
final class QSOLogPromptMessageTests: XCTestCase {

    /// Matches `QSOStatusManager.invalidSNR`.
    private let missing = Int.min

    var viewModel: FT8ViewModel!

    override func setUp() async throws {
        viewModel = FT8ViewModel()
        viewModel.callsign = "EA1ABC"
        viewModel.locator = "IM99"
        viewModel.qsoList.removeAll()
        viewModel.resetQSOState()
    }

    override func tearDown() async throws {
        viewModel = nil
    }

    private func entry(sent: Int, received: Int) -> LogEntry {
        viewModel.qsoManager.createLogEntry(
            dxCallsign: "EA2ABC",
            dxLocator: "FN31",
            qsoDate: .now,
            band: .band20m,
            isFT4: false,
            rstSent: sent,
            rstRcvd: received,
            isManualLog: true
        )
    }

    // MARK: - Message choice

    func testCompletedQSO_usesPlainConfirmation() {
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .completed, qso: entry(sent: -10, received: -8)), .confirm)
        // A completed QSO never claims anything about reports, so a gap does not change it.
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .completed, qso: entry(sent: -10, received: missing)), .confirm)
    }

    func testTimedOutWithBothReports_keepsTimeoutMessage() {
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .timedOut, qso: entry(sent: -10, received: -8)), .timedOut)
    }

    func testManualWithBothReports_doesNotMentionTimeout() {
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .manual, qso: entry(sent: -10, received: -8)), .manualBothReports)
    }

    /// The Crashlytics case: report sent, nothing received yet.
    func testManualWithoutReceivedReport_saysReceivedReportIsMissing() {
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .manual, qso: entry(sent: -4, received: missing)), .missingReceivedReport)
    }

    func testManualWithoutSentReport_saysSentReportIsMissing() {
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .manual, qso: entry(sent: missing, received: -8)), .missingSentReport)
    }

    func testManualWithoutAnyReport_saysBothAreMissing() {
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .manual, qso: entry(sent: missing, received: missing)), .missingBothReports)
    }

    /// A timed-out QSO should always have both reports, but if one is missing
    /// the alert must not claim otherwise.
    func testTimedOutWithMissingReport_neverClaimsBothWereExchanged() {
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .timedOut, qso: entry(sent: -10, received: missing)), .missingReceivedReport)
    }

    /// Older entries stored "Invalid" for a missing report.
    func testLegacyInvalidText_countsAsMissing() {
        let legacy = LogEntry(
            callsign: "EA2ABC",
            grid: "FN31",
            date: .now,
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "Invalid",
            stationCallsign: "EA1ABC",
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        XCTAssertEqual(QSOLogPromptMessage.make(reason: .manual, qso: legacy), .missingReceivedReport)
    }

    // MARK: - View model wiring

    /// "Log QSO" before the other station's report arrives: the prompt is
    /// flagged as manual and its message says the received report is missing.
    func testForceLogBeforeReport_promptsWithMissingReceivedReport() throws {
        viewModel.qsoManager.currentBand = .band20m
        viewModel.qsoManager.setupNewQSO(dx: "EA2ABC", locator: "FN31", initialSNR: -4)
        viewModel.qsoManager.qsoState = .listeningRRR(dxCallsign: "EA2ABC")

        viewModel.forceLogCurrentQSO()

        XCTAssertTrue(viewModel.showConfirmQSOAlert)
        XCTAssertEqual(viewModel.pendingLogReason, .manual)
        XCTAssertTrue(viewModel.pendingQSOIsUnconfirmed)
        let pending = try XCTUnwrap(viewModel.pendingQSOToLog)
        XCTAssertEqual(pending.rstSent, "-4")
        XCTAssertEqual(pending.rstRcvd, LogEntry.missingReport)
        XCTAssertEqual(
            QSOLogPromptMessage.make(reason: viewModel.pendingLogReason, qso: pending),
            .missingReceivedReport
        )
    }

    /// Cancelling clears the reason so the next normal prompt is not shown as incomplete.
    func testCancelLogging_resetsReason() {
        viewModel.offerLogging(qso: entry(sent: -10, received: -8), reason: .timedOut)
        XCTAssertEqual(viewModel.pendingLogReason, .timedOut)

        viewModel.cancelLogging()

        XCTAssertEqual(viewModel.pendingLogReason, .completed)
        XCTAssertFalse(viewModel.pendingQSOIsUnconfirmed)
        XCTAssertNil(viewModel.pendingQSOToLog)
    }

    /// A normal confirmation after a manual one goes back to the plain message.
    func testHandleQSOLogging_afterManualPrompt_resetsReason() {
        viewModel.autoQSOLogging = false
        viewModel.offerLogging(qso: entry(sent: -10, received: missing), reason: .manual)

        viewModel.handleQSOLogging(qso: entry(sent: -10, received: -8))

        XCTAssertEqual(viewModel.pendingLogReason, .completed)
        XCTAssertFalse(viewModel.pendingQSOIsUnconfirmed)
    }
}
