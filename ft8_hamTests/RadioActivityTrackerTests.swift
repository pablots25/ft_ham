//
//  RadioActivityTrackerTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/11/26.
//
//  transmission_success and transmission_failed were never sent: no caller
//  passed an outcome. These tests pin down when each one is logged.
//

import XCTest
@testable import ft8_ham

final class RadioActivityTrackerTests: XCTestCase {

    private typealias Name = RadioActivityTracker.EventName

    private var logger: MockAnalyticsLogger!
    private var clock: Date!
    private var tracker: RadioActivityTracker!

    override func setUp() {
        super.setUp()
        logger = MockAnalyticsLogger()
        clock = Date(timeIntervalSince1970: 1_000_000)
        tracker = RadioActivityTracker(logger: logger) { [unowned self] in self.clock }
    }

    override func tearDown() {
        tracker = nil
        logger = nil
        clock = nil
        super.tearDown()
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    // MARK: - Success

    func testCompletedTXLogsSuccess() {
        tracker.start(.tx)
        advance(13)
        tracker.stop(outcome: .completed)

        XCTAssertEqual(logger.events(named: Name.transmissionStarted).count, 1)
        XCTAssertEqual(logger.events(named: Name.transmissionSuccess).count, 1)
        XCTAssertTrue(logger.events(named: Name.transmissionFailed).isEmpty)
    }

    func testCompletedTXStillLogsUsage() {
        tracker.start(.tx)
        advance(13)
        tracker.stop(outcome: .completed)

        let usage = logger.events(named: Name.radioActivityUsage)
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage.first?.string(AnalyticsParam.activity), "tx")
        XCTAssertEqual(usage.first?.int(AnalyticsParam.durationSec), 13)
    }

    // MARK: - Failure

    func testInterruptedTXLogsFailureWithReason() {
        for reason in TransmissionFailureReason.allCases {
            logger.reset()
            tracker.start(.tx)
            tracker.stop(outcome: .interrupted(reason))

            let failed = logger.events(named: Name.transmissionFailed)
            XCTAssertEqual(failed.count, 1, "\(reason)")
            XCTAssertEqual(failed.first?.string(AnalyticsParam.reason), reason.rawValue)
            XCTAssertTrue(logger.events(named: Name.transmissionSuccess).isEmpty, "\(reason)")
        }
    }

    func testReasonWireValues() {
        XCTAssertEqual(TransmissionFailureReason.userStopped.rawValue, "user_stopped")
        XCTAssertEqual(TransmissionFailureReason.sequencerStopped.rawValue, "sequencer_stopped")
        XCTAssertEqual(TransmissionFailureReason.appBackground.rawValue, "app_background")
        XCTAssertEqual(TransmissionFailureReason.playbackFailed.rawValue, "playback_failed")
    }

    // MARK: - One outcome per TX

    /// stopCurrentTX reports the failure, then stopPlayback makes the audio
    /// manager publish "finished". That late callback is not a success.
    func testFinishCallbackAfterManualStopIsIgnored() {
        tracker.start(.tx)
        tracker.interruptTransmission(.userStopped)
        tracker.stop(outcome: .completed)

        XCTAssertEqual(logger.events(named: Name.transmissionFailed).count, 1)
        XCTAssertTrue(logger.events(named: Name.transmissionSuccess).isEmpty)
    }

    /// The sequencer cleanup runs before the async "finished" callback.
    func testFinishCallbackAfterSequencerStopIsIgnored() {
        tracker.start(.tx)
        tracker.stop(outcome: .interrupted(.sequencerStopped))
        tracker.stop(outcome: .completed)

        XCTAssertEqual(logger.events(named: Name.transmissionFailed).count, 1)
        XCTAssertTrue(logger.events(named: Name.transmissionSuccess).isEmpty)
    }

    func testSecondSuccessForSameTXIsIgnored() {
        tracker.start(.tx)
        tracker.stop(outcome: .completed)
        tracker.stop(outcome: .completed)

        XCTAssertEqual(logger.events(named: Name.transmissionSuccess).count, 1)
    }

    // MARK: - RX is not a transmission

    func testOutcomeIsIgnoredWhileReceiving() {
        tracker.start(.rx)
        advance(30)
        tracker.stop(outcome: .interrupted(.sequencerStopped))

        XCTAssertTrue(logger.events(named: Name.transmissionFailed).isEmpty)
        XCTAssertTrue(logger.events(named: Name.transmissionSuccess).isEmpty)
        XCTAssertEqual(logger.events(named: Name.radioActivityUsage).first?.string(AnalyticsParam.activity), "rx")
    }

    func testInterruptWhileReceivingKeepsRXRunning() {
        tracker.start(.rx)
        tracker.interruptTransmission(.userStopped)

        XCTAssertEqual(tracker.activeActivity, .rx)
        XCTAssertTrue(logger.events.isEmpty)
    }

    func testInterruptWithNothingRunningDoesNothing() {
        tracker.interruptTransmission(.playbackFailed)
        XCTAssertTrue(logger.events.isEmpty)
    }

    func testRXToTXHandOverLogsNoOutcome() {
        tracker.start(.rx)
        advance(20)
        tracker.start(.tx)

        XCTAssertEqual(logger.events.map(\.name), [Name.radioActivityUsage, Name.transmissionStarted])
        XCTAssertTrue(tracker.isTransmitting)
    }

    // MARK: - Usage timing (unchanged behaviour)

    func testShortActivityIsNotReported() {
        tracker.start(.tx)
        advance(2)
        tracker.stop(outcome: .completed)

        XCTAssertTrue(logger.events(named: Name.radioActivityUsage).isEmpty)
        XCTAssertEqual(logger.events(named: Name.transmissionSuccess).count, 1)
    }

    func testStartingSameActivityTwiceKeepsOneSession() {
        tracker.start(.tx)
        tracker.start(.tx)

        XCTAssertEqual(logger.events(named: Name.transmissionStarted).count, 1)
    }

    func testStopClearsActivity() {
        tracker.start(.tx)
        tracker.stop()

        XCTAssertNil(tracker.activeActivity)
        XCTAssertFalse(tracker.isTransmitting)
    }

    func testStopWithoutOutcomeLogsNoOutcome() {
        tracker.start(.tx)
        tracker.stop()

        XCTAssertTrue(logger.events(named: Name.transmissionSuccess).isEmpty)
        XCTAssertTrue(logger.events(named: Name.transmissionFailed).isEmpty)
    }
}
