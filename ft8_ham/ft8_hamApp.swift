//
//  ft8_hamApp.swift
//  ft_ham
//
//  Created by Pablo Turrion on 18/10/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        FirebaseApp.configure()

        configureAnalytics()
        configureCrashlytics()
        configureRemoteConfig()
        configureNotifications()

        return true
    }
}

// MARK: - Configuration

private extension AppDelegate {

    func configureAnalytics() {
        Analytics.setAnalyticsCollectionEnabled(true)

        #if DEBUG
        // Keep Analytics alive for Remote Config, but avoid event noise
        FirebaseConfiguration.shared.setLoggerLevel(.min)

        // Mark this build as developer for Remote Config segmentation
        Analytics.setUserProperty("developer", forName: "app_role")
        #else
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
        #endif
    }

    func configureCrashlytics() {
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        Crashlytics.crashlytics().setCustomValue("\(version) (\(build))", forKey: "app_version")
        Crashlytics.crashlytics().setCustomValue(UIDevice.current.systemVersion, forKey: "ios_version")
    }

    func configureRemoteConfig() {
        FeatureFlagManager.shared.refresh()
    }

    func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - SwiftUI App

@main
struct ft8_hamApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var viewModel = FT8ViewModel()
    @StateObject private var featureFlags = FeatureFlagManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(featureFlags)
                .modifier(QSOLogConfirmationModifier(manager: viewModel))
                .inAppPrompts()
        }
        .onChange(of: scenePhase) { newPhase in
            AnalyticsManager.shared.flushAllOnBackground(scenePhase: newPhase)
        }
    }
}
