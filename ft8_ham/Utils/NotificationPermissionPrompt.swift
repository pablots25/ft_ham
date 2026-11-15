//
//  NotificationPermissionPrompt.swift
//  ft_ham
//
//  Asks for notification permission the first time RX starts, when the
//  "RX paused in the background" alert it powers makes sense, instead of
//  during the onboarding.
//

import Foundation
import UserNotifications

enum NotificationPermissionPrompt {
    static let askedKey = "hasAskedNotificationPermission"

    /// True when the system dialog has not been shown yet and the app has
    /// not asked before.
    static func shouldRequest(status: UNAuthorizationStatus, alreadyAsked: Bool) -> Bool {
        status == .notDetermined && !alreadyAsked
    }

    /// Shows the system dialog once. Later calls do nothing.
    @MainActor
    static func requestIfNeeded(defaults: UserDefaults = .standard) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard shouldRequest(status: status, alreadyAsked: defaults.bool(forKey: askedKey)) else { return }
        defaults.set(true, forKey: askedKey)
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
}
