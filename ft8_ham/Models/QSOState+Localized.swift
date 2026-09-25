//
//  QSOState+Localized.swift
//  ft_ham
//
//  Created by Pablo Turrion on 25/09/26.
//

import Foundation

extension QSOState {

    /// User-facing, localized text for the current QSO step, naming the
    /// other station where the state has one.
    ///
    /// `description` stays as it is: it is English-only and goes to the logger.
    var localizedStatus: String {
        let peer = lockedCallsign.flatMap { $0.isEmpty ? nil : $0 } ?? Self.unknownPeer

        switch self {
        case .idle:
            return String(
                localized: "qso_state_idle",
                defaultValue: "No contact started",
                comment: "QSO status. No contact is in progress."
            )
        case .callingCQ:
            return String(
                localized: "qso_state_calling_cq",
                defaultValue: "Calling CQ…",
                comment: "QSO status. The app is calling CQ."
            )
        case .sendingGrid:
            return String(
                localized: "qso_state_sending_grid",
                defaultValue: "Sending grid to \(peer)…",
                comment: "QSO status. The argument is the other station's callsign."
            )
        case .sendingReport:
            return String(
                localized: "qso_state_sending_report",
                defaultValue: "Sending signal report to \(peer)…",
                comment: "QSO status. The argument is the other station's callsign."
            )
        case .listeningReport:
            return String(
                localized: "qso_state_listening_report",
                defaultValue: "Waiting for a signal report from \(peer)…",
                comment: "QSO status. The argument is the other station's callsign."
            )
        case .sendingRReport:
            return String(
                localized: "qso_state_sending_r_report",
                defaultValue: "Sending R report to \(peer)…",
                comment: "QSO status. R report is the roger plus signal report message. The argument is the other station's callsign."
            )
        case .listeningRReport:
            return String(
                localized: "qso_state_listening_r_report",
                defaultValue: "Waiting for RRR or RR73 from \(peer)…",
                comment: "QSO status. RRR and RR73 are FT8 protocol tokens, do not translate them. The argument is the other station's callsign."
            )
        case .sendingRRR:
            return String(
                localized: "qso_state_sending_rrr",
                defaultValue: "Sending RRR to \(peer)…",
                comment: "QSO status. RRR is an FT8 protocol token, do not translate it. The argument is the other station's callsign."
            )
        case .listeningRRR:
            return String(
                localized: "qso_state_listening_rrr",
                defaultValue: "Waiting for 73 from \(peer)…",
                comment: "QSO status. 73 is the ham radio sign-off, do not translate it. The argument is the other station's callsign."
            )
        case .sending73:
            return String(
                localized: "qso_state_sending_73",
                defaultValue: "Sending 73 to \(peer)…",
                comment: "QSO status. 73 is the ham radio sign-off, do not translate it. The argument is the other station's callsign."
            )
        case .completed:
            return String(
                localized: "qso_state_completed",
                defaultValue: "QSO with \(peer) complete",
                comment: "QSO status. The argument is the other station's callsign."
            )
        case .timeout:
            return String(
                localized: "qso_state_timeout",
                defaultValue: "No reply from \(peer), retries used up",
                comment: "QSO status. The contact was abandoned after the retry limit. The argument is the other station's callsign."
            )
        }
    }

    /// Stands in for the callsign when a state has none.
    private static var unknownPeer: String {
        String(
            localized: "qso_peer_unknown",
            defaultValue: "the other station",
            comment: "Stands in for the other station's callsign in a QSO status when it is not known."
        )
    }
}
