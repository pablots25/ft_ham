//
//  RootUIState.swift
//  ft_ham
//
//  Small observable objects owned by FT8ViewModel that expose only the state
//  needed near the root of the view tree. Views observing these objects are not
//  invalidated by the (very frequent) publishes of the full FT8ViewModel.
//

import Foundation
import Combine

/// State read by `ContentView` and the app root: toast banner, whether the
/// station is configured, and the current mode (for the header progress bar).
@MainActor
final class RootUIState: ObservableObject {
    @Published var toast: ToastMessage?
    /// Presents the free-text TX sheet. It lives here, not in
    /// `TransmissionButtonsBar`, because that bar re-renders on every view
    /// model publish — a sheet anchored inside it is torn down and
    /// re-presented while you type.
    @Published var showFreeTextSheet: Bool = false
    @Published var settingsLoaded: Bool = false
    @Published var isFT4: Bool = false
}

/// State backing the "Confirm QSO logging" alert. Observed only by
/// `QSOLogConfirmationModifier`, which sits above `ContentView`.
@MainActor
final class QSOLogPrompt: ObservableObject {
    @Published var showConfirmQSOAlert: Bool = false
    @Published var pendingQSOToLog: LogEntry?
    @Published var pendingReason: QSOLogPromptReason = .completed

    /// True when the pending QSO did not finish its handshake.
    var pendingQSOIsUnconfirmed: Bool { pendingReason != .completed }
}

/// Why the log confirmation alert is shown. It decides the alert's wording.
enum QSOLogPromptReason: Equatable {
    /// The QSO finished normally and auto-logging is off.
    case completed
    /// The sequencer gave up waiting for the final 73 after the reports were exchanged.
    case timedOut
    /// The operator pressed "Log QSO" while the QSO was still in progress.
    case manual
}

/// The message the log confirmation alert shows. Kept apart from the view so
/// the choice can be unit tested: the alert must never claim a report was
/// exchanged when it was not.
enum QSOLogPromptMessage: Equatable {
    case confirm
    case timedOut
    case manualBothReports
    case missingReceivedReport
    case missingSentReport
    case missingBothReports

    static func make(reason: QSOLogPromptReason, qso: LogEntry) -> QSOLogPromptMessage {
        guard reason != .completed else { return .confirm }

        let hasSent = LogEntry.adifReport(qso.rstSent) != nil
        let hasReceived = LogEntry.adifReport(qso.rstRcvd) != nil

        switch (hasSent, hasReceived) {
        case (false, false):
            return .missingBothReports
        case (true, false):
            return .missingReceivedReport
        case (false, true):
            return .missingSentReport
        case (true, true):
            return reason == .timedOut ? .timedOut : .manualBothReports
        }
    }
}
