//
//  QSOCallsignSwitchingTests.swift
//  ft_hamTests
//
//  Tests for callsign switching logic and interleaved QSO handling
//  Ensures proper rejection of interfering stations during active QSOs
//

import XCTest
@testable import ft8_ham

@MainActor
final class QSOCallsignSwitchingTests: XCTestCase {

    private var manager: QSOStatusManager!
    private let myCallsign = "EA1TST"
    private let myLocator = "IN70"
    private let stationA = "K1ABC"
    private let stationB = "W5XYZ"
    private let locatorA = "FN20"
    private let locatorB = "EM29"

    override func setUp() {
        super.setUp()
        manager = QSOStatusManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Tests for Callsign Switching Protection

    func testProperlyLocksToFirstResponder() {
        // Test that the manager properly locks to the first responding station
        // and maintains that lock even when signals from other stations are received

        // Create a CQ message from Station A with measurable SNR
        let cqMessageA = FT8Message(
            text: "CQ \(stationA) \(locatorA)",
            mode: .ft8,
            measuredSNR: -8.0,
            band: .band20m
        )

        manager.startReply(
            to: cqMessageA,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        XCTAssertEqual(manager.lockedDXCallsign, stationA, "Should lock to Station A")
        XCTAssertEqual(manager.lastSentSNR, -8, "RST_SENT should be frozen at start")
    }

    func testLockedSNRNotOverwrittenByOtherStations() {
        // Test that once we have a valid SNR stored for our locked station,
        // we don't overwrite it with SNR from interfering stations

        let cqMessageA = FT8Message(
            text: "CQ \(stationA) \(locatorA)",
            mode: .ft8,
            measuredSNR: -8.0,
            band: .band20m
        )

        manager.startReply(
            to: cqMessageA,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        let sentSNRAtStart = manager.lastSentSNR
        XCTAssertEqual(sentSNRAtStart, -8, "RST_SENT should be frozen")

        // Now another station sends a grid exchange
        // The important part is this has different SNR than what we locked to
        let gridFromB = FT8Message(
            text: "\(myCallsign) \(stationB) \(locatorB)",
            mode: .ft8,
            measuredSNR: -12.0,
            band: .band20m
        )

        let replyAction = manager.handleIncomingMessage(
            gridFromB,
            myCallsign: myCallsign,
            autoSequencingEnabled: true,
            autoCQReplyEnabled: true
        )

        // Should ignore Station B's grid while locked to A  
        XCTAssertEqual(replyAction, .ignore, "Should ignore grid from Station B")
        XCTAssertEqual(manager.lockedDXCallsign, stationA, "Should remain locked to Station A")
        XCTAssertEqual(manager.lastSentSNR, sentSNRAtStart, "RST_SENT should not change")
    }

    func testResetClearsLockAndSNRs() {
        // Test that resetting properly clears both the DX lock and SNR values
        let cqMessageA = FT8Message(
            text: "CQ \(stationA) \(locatorA)",
            mode: .ft8,
            measuredSNR: -8.0,
            band: .band20m
        )

        manager.startReply(
            to: cqMessageA,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        XCTAssertNotEqual(manager.lastSentSNR, Int.min, "RST_SENT should be valid")
        XCTAssertEqual(manager.lockedDXCallsign, stationA, "Should be locked to Station A")

        // Reset the radio state as we would after QSO completion
        manager.resetRadioStateAfterCompletion()

        XCTAssertEqual(manager.lastSentSNR, Int.min, "RST_SENT should be reset to invalid")
        XCTAssertEqual(manager.lockedDXCallsign, "", "DX lock should be cleared")
    }

    func testNewQSOUsesNewSNRNotStaleValues() {
        // Test that after completing one QSO and starting a new one,
        // we use new SNR values and don't retain stale values from the previous QSO

        let cqMessageA = FT8Message(
            text: "CQ \(stationA) \(locatorA)",
            mode: .ft8,
            measuredSNR: -8.0,
            band: .band20m
        )

        manager.startReply(
            to: cqMessageA,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        let firstQSOSentSNR = manager.lastSentSNR
        XCTAssertEqual(firstQSOSentSNR, -8)

        // Complete the QSO
        manager.resetRadioStateAfterCompletion()

        // Verify SNRs are clear
        XCTAssertEqual(manager.lastSentSNR, Int.min)

        // Start new QSO with different station and different SNR
        let cqMessageB = FT8Message(
            text: "CQ \(stationB) \(locatorB)",
            mode: .ft8,
            measuredSNR: -5.0,
            band: .band20m
        )

        manager.startReply(
            to: cqMessageB,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        // New QSO should have new SNR
        XCTAssertEqual(manager.lastSentSNR, -5, "New QSO should use new SNR")
        XCTAssertEqual(manager.lockedDXCallsign, stationB, "Should be locked to Station B")
        XCTAssertNotEqual(manager.lastSentSNR, firstQSOSentSNR, "Should not retain stale SNR from previous QSO")
    }

    func testValidLogEntryWithGoodSNRs() {
        // Test that we can create a valid log entry when SNRs are populated

        let rstSent = -8
        let rstRcvd = -10

        let logEntry = manager.createLogEntry(
            dxCallsign: stationA,
            dxLocator: locatorA,
            qsoDate: .now,
            band: .band40m,
            isFT4: false,
            rstSent: rstSent,
            rstRcvd: rstRcvd
        )

        XCTAssertEqual(logEntry.callsign, stationA, "Log should record DX callsign")
        XCTAssertEqual(logEntry.rstSent, "-8", "Log RST_SENT should be valid number")
        XCTAssertEqual(logEntry.rstRcvd, "-10", "Log RST_RCVD should be valid number")
        XCTAssertNotEqual(logEntry.rstSent, "Invalid", "Should not mark valid RST_SENT as Invalid")
    }

    func testInvalidLogEntryHandling() {
        // Test that we properly mark log entries as Invalid when SNRs are missing

        let logEntry = manager.createLogEntry(
            dxCallsign: stationA,
            dxLocator: locatorA,
            qsoDate: .now,
            band: .band40m,
            isFT4: false,
            rstSent: Int.min,
            rstRcvd: -10
        )

        XCTAssertEqual(logEntry.rstSent, "Invalid", "Should mark RST_SENT as Invalid when missing")
        XCTAssertEqual(logEntry.rstRcvd, "Invalid", "Should mark RST_RCVD as Invalid when partner SNR missing")
    }

    func testMultipleCallsignValidation() {
        // Test the isReportFromLockedDX helper method  

        let cqMessageA = FT8Message(
            text: "CQ \(stationA) \(locatorA)",
            mode: .ft8,
            measuredSNR: -8.0,
            band: .band20m
        )

        manager.startReply(
            to: cqMessageA,
            myCallsign: myCallsign,
            myLocator: myLocator
        )

        // Message from locked station A addressed to us should validate
        let reportA = FT8Message(
            text: "\(myCallsign) \(stationA) -10:00",
            mode: .ft8,
            measuredSNR: -10.0,
            band: .band20m
        )

        let isValidA = manager.isReportFromLockedDX(reportA, myCallsign: myCallsign)
        XCTAssertTrue(isValidA, "Report from locked DX should validate")

        // Message from different station B should not validate
        let reportB = FT8Message(
            text: "\(myCallsign) \(stationB) -12:00",
            mode: .ft8,
            measuredSNR: -12.0,
            band: .band20m
        )

        let isValidB = manager.isReportFromLockedDX(reportB, myCallsign: myCallsign)
        XCTAssertFalse(isValidB, "Report from non-locked station should not validate")
    }
}
