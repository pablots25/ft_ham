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
#if canImport(TipKit)
import TipKit
#endif

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard AppEnvironment.current.isProduction else { return true }

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
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        return
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        Crashlytics.crashlytics().setCustomValue("\(version) (\(build))", forKey: "app_version")
        Crashlytics.crashlytics().setCustomValue(UIDevice.current.systemVersion, forKey: "ios_version")
    }

    func configureRemoteConfig() {
        // Explicitly refresh all Firebase Remote Config variables at app launch
        let provider = RemoteConfigProvider()
        let logger = AppLogger(category: "APPINIT")
        
        logger.debug("🔄 Starting Firebase Remote Config synchronization...")
        provider.refreshAllFlags { [weak provider] in
            if let provider = provider {
                logger.debug(provider.getConfigurationSummary())
            }
            // After initial fetch, start the periodic refresh in FeatureFlagManager
            FeatureFlagManager.shared.refresh()
        }
    }

    func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Authorization request with empty handler - notification handling is done in userNotificationCenter(_:willPresent:withCompletionHandler:)
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
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
                .environmentObject(FeatureFlagManager.shared)
                .environmentObject(featureFlags)
                .modifier(QSOLogConfirmationModifier(manager: viewModel))
                .inAppPrompts()
                .task {
#if canImport(TipKit)
                    if #available(iOS 17.0, *) {
                        try? await Tips.configure()
                    }
#endif
                }
        }
        .onChange(of: scenePhase) { newPhase in
            AnalyticsManager.shared.flushAllOnBackground(scenePhase: newPhase)

            switch newPhase {
            case .background:
                if viewModel.isSequencerRunning {
                    Task { @MainActor in
                        await viewModel.stopSequencer(rememberState: true)
                        NotificationHelper.sendSequencerPausedNotification()
                    }
                }
            case .active:
                NotificationHelper.cancelSequencerPausedNotification()
                Task { @MainActor in
                    if viewModel.wasSequencerRunningBeforeBackground {
                        if featureFlags.isEnabled(.backgroundToast) {
                            viewModel.toast = .warning(String(localized: "bg_toast_message"))
                        }
                        await viewModel.stopSequencer()
                        viewModel.wasSequencerRunningBeforeBackground = false
                        guard viewModel.settingsLoaded else { return }
                        viewModel.startSequencer()
                    }
                }
            default:
                break
            }
        }
    }
}
