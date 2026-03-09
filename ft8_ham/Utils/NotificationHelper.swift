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

    /// Removes the pending or delivered sequencer-paused notification when the app returns to foreground.
    static func cancelSequencerPausedNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [sequencerPausedID])
        center.removeDeliveredNotifications(withIdentifiers: [sequencerPausedID])
    }
}
