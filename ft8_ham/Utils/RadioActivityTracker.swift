//
//  RadioActivityTracker.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/11/26.
//

import Foundation

/// Why a transmission ended before its audio finished, sent as `reason` on
/// `transmission_failed`.
enum TransmissionFailureReason: String, CaseIterable {
    /// The user stopped the current TX.
    case userStopped = "user_stopped"
    /// The sequencer stopped (RX off, band or mode change, restart) mid TX.
    case sequencerStopped = "sequencer_stopped"
    /// The app went to the background mid TX.
    case appBackground = "app_background"
    /// The audio engine refused to play the TX audio.
    case playbackFailed = "playback_failed"
}

/// How a transmission ended.
enum TransmissionOutcome: Equatable {
    /// The TX audio played to the end.
    case completed
    /// The TX was cut before its audio finished.
    case interrupted(TransmissionFailureReason)
}

/// Times RX and TX for `radio_activity_usage` and reports how each
/// transmission ends (`transmission_started`, then `transmission_success` or
/// `transmission_failed`).
///
/// Only one activity runs at a time. A TX outcome is reported once: whatever
/// ends the TX first wins, so the audio's own "finished" callback that follows
/// a manual stop does not count as a success.
final class RadioActivityTracker {

    enum EventName {
        static let transmissionStarted = "transmission_started"
        static let transmissionSuccess = "transmission_success"
        static let transmissionFailed = "transmission_failed"
        static let radioActivityUsage = "radio_activity_usage"
    }

    /// Activities shorter than this are dropped from `radio_activity_usage`.
    static let minimumReportedDuration = 2

    private weak var logger: AnalyticsLogging?
    private let now: () -> Date

    private(set) var activeActivity: RadioActivityType?
    private var startTime: Date?

    init(logger: AnalyticsLogging, now: @escaping () -> Date = Date.init) {
        self.logger = logger
        self.now = now
    }

    var isTransmitting: Bool { activeActivity == .tx }

    /// Starts timing `activity`, closing the one in progress. A new TX logs
    /// `transmission_started`.
    func start(_ activity: RadioActivityType) {
        guard activeActivity != activity else { return }

        // RX → TX is the normal hand-over. A TX replaced by another activity
        // never got an outcome, so it is left without one rather than guessed.
        flushUsage()

        activeActivity = activity
        startTime = now()

        if activity == .tx {
            logger?.logEvent(EventName.transmissionStarted, parameters: nil)
        }
    }

    /// Stops timing. `outcome` is reported only when a TX is in progress, so
    /// callers can pass it without checking what is running.
    func stop(outcome: TransmissionOutcome? = nil) {
        if isTransmitting, let outcome {
            report(outcome)
        }
        flushUsage()
    }

    /// Ends the TX in progress as interrupted. Does nothing when no TX is
    /// running, so an RX session is left untouched.
    func interruptTransmission(_ reason: TransmissionFailureReason) {
        guard isTransmitting else { return }
        stop(outcome: .interrupted(reason))
    }

    // MARK: - Private

    private func report(_ outcome: TransmissionOutcome) {
        switch outcome {
        case .completed:
            logger?.logEvent(EventName.transmissionSuccess, parameters: nil)
        case .interrupted(let reason):
            logger?.logEvent(EventName.transmissionFailed, parameters: [
                AnalyticsParam.reason: reason.rawValue
            ])
        }
    }

    private func flushUsage() {
        defer {
            activeActivity = nil
            startTime = nil
        }
        guard let activity = activeActivity, let startTime else { return }

        let duration = Int(now().timeIntervalSince(startTime))
        guard duration > Self.minimumReportedDuration else { return }

        logger?.logEvent(EventName.radioActivityUsage, parameters: [
            AnalyticsParam.activity: activity.rawValue,
            AnalyticsParam.durationSec: NSNumber(value: duration)
        ])
    }
}
