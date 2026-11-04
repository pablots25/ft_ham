//
//  CallAlertDetector.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/09/26.
//

import Foundation

/// Decides which decoded messages are another station calling us, and whether
/// a slot should raise a "calling you" alert (sound, haptic, notification).
enum CallAlertDetector {

    /// True when `msg` is a received message addressed to `myCallsign` by
    /// another station. Our own transmissions, timestamps and free text are
    /// never a call to us.
    static func isCallingMe(_ msg: FT8Message, myCallsign: String) -> Bool {
        guard !msg.isTX,
              msg.msgType != .internalTimestamp, msg.msgType != .unknown else { return false }

        let my = myCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !my.isEmpty,
              let receiver = msg.dxCallsign?.uppercased(), receiver == my else { return false }

        return msg.callsign?.uppercased() != my
    }

    /// True while no QSO is being worked, so an incoming call is news to the
    /// operator. During an active exchange every slot would otherwise alert.
    static func allowsAlert(in qsoState: QSOState) -> Bool {
        switch qsoState {
        case .idle, .callingCQ, .completed, .timeout:
            return true
        case .sendingGrid, .sendingReport, .listeningReport,
             .sendingRReport, .listeningRReport,
             .sendingRRR, .listeningRRR, .sending73:
            return false
        }
    }

    /// The message a slot should alert for: the first one calling us, or nil
    /// when none does or a QSO is already in progress.
    static func alertMessage(
        in messages: [FT8Message],
        myCallsign: String,
        qsoState: QSOState
    ) -> FT8Message? {
        guard allowsAlert(in: qsoState) else { return nil }
        return messages.first { isCallingMe($0, myCallsign: myCallsign) }
    }
}
