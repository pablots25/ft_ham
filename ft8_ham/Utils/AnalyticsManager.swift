//
//  AnalyticsManager.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 2026-01-04.
//

import Foundation
import Firebase
import FirebaseAnalytics
import SwiftUI

enum AnalyticsScreen: String {
    case home
    case txRx = "tx_rx"
    case waterfall
    case map
    case logbook
    case configuration
    case onboarding
    case terms
}

enum RadioActivityType: String {
    case tx
    case rx
}

/// Singleton manager to handle anonymous app metrics, App Store compliant.
final class AnalyticsManager {

    private let appLogger = AppLogger(category: "ANL")

    // MARK: - Singleton
    static let shared = AnalyticsManager()

    // MARK: - Radio Activity State
    private var activeRadioActivity: RadioActivityType?
    private var radioActivityStartTime: Date?

    private init() {
        UserDefaults.standard.register(defaults: ["analyticsEnabled": true])

        #if DEBUG
        self.isAnalyticsEnabled = false
        #else
        let saved = UserDefaults.standard.bool(forKey: "analyticsEnabled")
        self.isAnalyticsEnabled = saved
        Analytics.setAnalyticsCollectionEnabled(saved)
        #endif
    }

    // MARK: - Properties
    private var sessionDecodedMessages: Int = 0
    private var sessionQSOs: Int = 0

    /// Internal toggle to enable/disable data collection
    var isAnalyticsEnabled: Bool {
        didSet {
            #if !DEBUG
            UserDefaults.standard.set(isAnalyticsEnabled, forKey: "analyticsEnabled")
            Analytics.setAnalyticsCollectionEnabled(isAnalyticsEnabled)
            #endif
        }
    }

    // MARK: - Firebase Lifecycle
    func configureFirebase() {
        #if !DEBUG
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(isAnalyticsEnabled)
        #endif
    }

    // MARK: - App Lifecycle
    func logAppOpened() {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
    }

    // MARK: - Onboarding & Legal

    func logOnboardingCompleted() {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("onboarding_completed", parameters: nil)
    }

    func logTermsAccepted() {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("terms_accepted", parameters: nil)
    }

    // MARK: - Rate & Share Events

    func logRateConfirmed() {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("rate_confirmed", parameters: nil)
    }

    func logRatePostponed() {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("rate_postponed", parameters: nil)
    }

    func logShareCompleted() {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("share_completed", parameters: nil)
    }

    // MARK: - Configuration

    func logConfigurationSaved() {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("configuration_saved", parameters: nil)
    }

    // MARK: - Radio Activity Tracking

    func startRadioActivity(_ activity: RadioActivityType) {
        guard isAnalyticsEnabled else { return }
        guard activeRadioActivity != activity else { return }

        flushRadioActivityUsage()

        activeRadioActivity = activity
        radioActivityStartTime = Date()

        if activity == .tx {
            Analytics.logEvent("transmission_started", parameters: nil)
        }
    }

    func stopRadioActivity(success: Bool? = nil, failureReason: String? = nil) {
        if let success {
            if success {
                Analytics.logEvent("transmission_success", parameters: nil)
            } else {
                Analytics.logEvent("transmission_failed", parameters: [
                    "reason": failureReason ?? "unknown"
                ])
            }
        }
        flushRadioActivityUsage()
    }

    private func flushRadioActivityUsage() {
        guard
            isAnalyticsEnabled,
            let activity = activeRadioActivity,
            let start = radioActivityStartTime
        else { return }

        let duration = Int(Date().timeIntervalSince(start))
        guard duration > 2 else {
            activeRadioActivity = nil
            radioActivityStartTime = nil
            return
        }

        Analytics.logEvent("radio_activity_usage", parameters: [
            "activity": activity.rawValue,
            "duration_sec": duration
        ])

        activeRadioActivity = nil
        radioActivityStartTime = nil
    }

    // MARK: - Decoded Messages Logic

    func addDecodedMessages(count: Int = 1) {
        sessionDecodedMessages += count
    }

    func flushDecodedMessages() {
        guard isAnalyticsEnabled, sessionDecodedMessages > 0 else { return }
        Analytics.logEvent("messages_decoded", parameters: [
            "count": sessionDecodedMessages
        ])
        sessionDecodedMessages = 0
    }

    // MARK: - QSO Logic

    func addQSOs(count: Int = 1) {
        sessionQSOs += count
    }

    func flushQSOs() {
        guard isAnalyticsEnabled, sessionQSOs > 0 else { return }
        Analytics.logEvent("qso_logged", parameters: [
            "count": sessionQSOs
        ])
        sessionQSOs = 0
    }

    // MARK: - ADIF Export

    func logADIFExport(qsoCount: Int, exportType: String = "file") {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("adif_export", parameters: [
            "qso_count": qsoCount,
            "export_type": exportType
        ])
    }

    // MARK: - Background Management

    func flushAllOnBackground(scenePhase: ScenePhase) {
        if scenePhase == .background || scenePhase == .inactive {
            flushDecodedMessages()
            flushQSOs()
            stopRadioActivity()
        }
    }

    // MARK: - Screen Tracking

    func trackScreen(_ screen: AnalyticsScreen) {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent(
            AnalyticsEventScreenView,
            parameters: [
                AnalyticsParameterScreenName: screen.rawValue,
                AnalyticsParameterScreenClass: "SwiftUI"
            ]
        )
    }

    func trackViewMode(_ mode: ViewMode) {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("view_mode_selected", parameters: [
            "view_mode": mode.rawValue.lowercased()
        ])
    }

    func trackRadioModeChange(isFT4: Bool) {
        guard isAnalyticsEnabled else { return }
        Analytics.logEvent("radio_mode_changed", parameters: [
            "radio_mode": isFT4 ? "ft4" : "ft8"
        ])
    }
}
