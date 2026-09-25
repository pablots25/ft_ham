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

    /// Fixed identifier of the "calling you" banner, so a new alert replaces
    /// the previous one.
    static let callAlertID = "call_alert"
    /// Category of the "QSO logged" notification.
    static let qsoLoggedCategoryID = "QSO_CATEGORY"
    /// Action on the "QSO logged" notification that opens the logbook.
    static let reviewQSOActionID = "REVIEW_QSO"

    /// Registers the notification categories and their actions. Call once at
    /// startup, not every time a notification is posted.
    static func registerCategories() {
        let reviewAction = UNNotificationAction(
            identifier: reviewQSOActionID,
            title: String(localized: "Review QSO"),
            options: [.foreground]
        )
        let qsoLogged = UNNotificationCategory(
            identifier: qsoLoggedCategoryID,
            actions: [reviewAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([qsoLogged])
    }

    /// How a notification is shown while the app is in the foreground.
    /// - A logged QSO shows nothing, because the app already reports it.
    /// - A "calling you" alert shows a silent banner. The sound setting plays
    ///   its own chime only on safe audio routes.
    /// - Anything else keeps a banner with sound.
    static func foregroundPresentationOptions(
        identifier: String,
        categoryIdentifier: String
    ) -> UNNotificationPresentationOptions {
        if categoryIdentifier == qsoLoggedCategoryID { return [] }
        if identifier == callAlertID { return [.banner] }
        return [.banner, .sound]
    }

    /// True when a response to a notification should open the Logbook tab:
    /// the "Review QSO" action or a tap on a "QSO logged" notification.
    static func opensLogbook(actionIdentifier: String, categoryIdentifier: String) -> Bool {
        if actionIdentifier == reviewQSOActionID { return true }
        return categoryIdentifier == qsoLoggedCategoryID
            && actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    /// Clears the app icon badge. Older builds set it to the logbook size.
    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }

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
