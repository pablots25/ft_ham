//
//  NotificationHelper.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/3/26.
//

import UserNotifications

enum NotificationHelper {

    private static let sequencerPausedID = "sequencer_paused_background"

    /// Fires an immediate local notification informing the user that RX/TX was paused.
    static func sendSequencerPausedNotification() {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                return
            }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "bg_notification_title")
            content.body  = String(localized: "bg_notification_body")
            content.sound = .none

            // Fires after 1 second (minimum allowed interval; nil trigger is not supported for local)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

            let request = UNNotificationRequest(
                identifier: sequencerPausedID,
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    private static let callAlertID = "call_alert"

    /// Shows a banner when a decoded message calls our callsign or comes from
    /// a watched station. Reuses one identifier so repeated alerts replace the
    /// banner instead of stacking. Silent: the separate sound setting decides
    /// whether a chime plays.
    static func sendCallAlertNotification(_ kind: CallAlertKind, from callsign: String, text: String) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                return
            }

            let content = UNMutableNotificationContent()
            switch kind {
            case .callingMe:
                content.title = callsign.isEmpty
                    ? String(localized: "A station is calling you")
                    : String(localized: "\(callsign) is calling you")
            case .watched:
                content.title = String(localized: "\(callsign) is on the air")
            }
            content.body = text
            content.sound = nil

            let request = UNNotificationRequest(
                identifier: callAlertID,
                content: content,
                trigger: nil
            )

            center.add(request)
        }
    }

    /// Removes the pending or delivered sequencer-paused notification when the app returns to foreground.
    static func cancelSequencerPausedNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [sequencerPausedID])
        center.removeDeliveredNotifications(withIdentifiers: [sequencerPausedID])
    }
}
