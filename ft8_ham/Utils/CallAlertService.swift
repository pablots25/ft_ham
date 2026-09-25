//
//  CallAlertService.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/09/26.
//

import AudioToolbox
import AVFoundation
import UIKit

/// Why a decoded message raised an alert.
enum CallAlertKind: Equatable {
    /// Another station calls our callsign.
    case callingMe
    /// A station on the watchlist was heard.
    case watched
}

/// Raises the alerts chosen in Display settings.
@MainActor
protocol CallAlerting: AnyObject {
    func alert(_ kind: CallAlertKind, for message: FT8Message, sound: Bool, haptic: Bool, notification: Bool)
}

@MainActor
final class CallAlertService: CallAlerting {

    private enum Constants {
        /// Short tri-tone from the system sound set.
        static let alertSoundID: SystemSoundID = 1007
    }

    nonisolated init() {}

    func alert(_ kind: CallAlertKind, for message: FT8Message, sound: Bool, haptic: Bool, notification: Bool) {
        if sound {
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
            if Self.isSafeRouteForAlertSound(outputs) {
                AudioServicesPlaySystemSound(Constants.alertSoundID)
            }
        }
        if haptic {
            Haptics.warning()
        }
        if notification {
            NotificationHelper.sendCallAlertNotification(
                kind,
                from: message.callsign ?? "",
                text: message.text
            )
        }
    }

    /// True when every output port is one the operator hears directly. A USB
    /// or line interface usually feeds the radio, where a chime could be
    /// transmitted or trip VOX, so the sound is skipped there.
    nonisolated static func isSafeRouteForAlertSound(_ outputs: [AVAudioSession.Port]) -> Bool {
        let safe: Set<AVAudioSession.Port> = [
            .builtInSpeaker, .builtInReceiver, .headphones,
            .bluetoothA2DP, .bluetoothHFP, .bluetoothLE
        ]
        return !outputs.isEmpty && outputs.allSatisfy { safe.contains($0) }
    }
}
