//
//  AnalyticsManager.swift
//  ft_ham
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
    case ipadDashboard = "ipad_dashboard"
    case logbook
    case configuration
    case onboarding
    case terms
    case whatsNew = "whats_new"
}

enum RadioActivityType: String {
    case tx
    case rx
}

enum AnalyticsParam {
    static let triggerSource = "trigger_source"
    static let reason = "reason"
    static let appLaunches = "app_launches"
    static let roll = "roll"
    static let activity = "activity"
    static let durationSec = "duration_sec"
    static let count = "count"
    static let qsoCount = "qso_count"
    static let exportType = "export_type"
    static let viewMode = "view_mode"
    static let radioMode = "radio_mode"
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
        let initialValue = false
        #else
        let initialValue = UserDefaults.standard.bool(forKey: "analyticsEnabled")
        #endif

        self.isAnalyticsEnabled = initialValue
        Analytics.setAnalyticsCollectionEnabled(initialValue)
    }


    // MARK: - Properties
    private var sessionDecodedMessages: Int = 0
    private var sessionQSOs: Int = 0

    /// Internal toggle to enable/disable data collection
    var isAnalyticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAnalyticsEnabled, forKey: "analyticsEnabled")
            Analytics.setAnalyticsCollectionEnabled(isAnalyticsEnabled)
            Analytics.setConsent([
                .analyticsStorage: isAnalyticsEnabled ? .granted : .denied
            ])
        }
    }

    // MARK: - Consent Mode

    /// Must be called **before** `FirebaseApp.configure()` at every app launch.
    /// Sets default consent signals based on whether the user has previously accepted the terms.
    static func applyConsentBeforeConfigure() {
        let hasAccepted = UserDefaults.standard.bool(forKey: "hasAcceptedTerms")
        Analytics.setConsent([
            .analyticsStorage: hasAccepted ? .granted : .denied,
            .adStorage: .denied,
            .adUserData: .denied,
            .adPersonalization: .denied
        ])
    }

    /// Grants analytics consent after the user accepts the terms. Call this when the user taps "I Accept".
    func grantAnalyticsConsent() {
        Analytics.setConsent([.analyticsStorage: .granted])
    }

    // MARK: - Central Event Logger

    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isAnalyticsEnabled else { return }
        appLogger.debug("Analytics event: \(name) \(parameters ?? [:])")
        Analytics.logEvent(name, parameters: parameters)
    }

    // MARK: - App Lifecycle
    func logAppOpened() {
        logEvent(AnalyticsEventAppOpen)
    }

    // MARK: - Onboarding & Legal

    func logOnboardingCompleted() {
        logEvent("onboarding_completed")
    }

    func logTermsAccepted() {
        logEvent("terms_accepted")
    }

    // MARK: - Rate & Share Events

    func logRatePromptShown() {
        logEvent("rate_prompt_shown")
    }

    func logRateConfirmed() {
        logEvent("rate_confirmed")
    }

    func logRatePostponed() {
        logEvent("rate_postponed")
    }

    func logShareCompleted() {
        logEvent("share_completed")
    }

    func logSharePromptShown() {
        logEvent("share_prompt_shown")
    }

    func logSharePromptPostponed() {
        logEvent("share_prompt_postponed")
    }

    // MARK: - Donation Events

    func logDonationPromptShown(triggerSource: String, appLaunches: Int) {
        logEvent("donation_prompt_shown", parameters: [
            AnalyticsParam.triggerSource: triggerSource,
            AnalyticsParam.appLaunches: NSNumber(value: appLaunches)
        ])
    }

    func logDonationPromptConfirmed(triggerSource: String, appLaunches: Int) {
        logEvent("donation_prompt_confirmed", parameters: [
            AnalyticsParam.triggerSource: triggerSource,
            AnalyticsParam.appLaunches: NSNumber(value: appLaunches)
        ])
    }

    func logDonationPromptPostponed(triggerSource: String, appLaunches: Int) {
        logEvent("donation_prompt_postponed", parameters: [
            AnalyticsParam.triggerSource: triggerSource,
            AnalyticsParam.appLaunches: NSNumber(value: appLaunches)
        ])
    }

    func logDonationPromptSkipped(triggerSource: String, reason: String, appLaunches: Int, roll: Int? = nil) {
        var parameters: [String: Any] = [
            AnalyticsParam.triggerSource: triggerSource,
            AnalyticsParam.reason: reason,
            AnalyticsParam.appLaunches: NSNumber(value: appLaunches)
        ]

        if let roll {
            parameters[AnalyticsParam.roll] = NSNumber(value: roll)
        }

        logEvent("donation_prompt_skipped", parameters: parameters)
    }

    func logPurchaseCompleted(productID: String, value: Double? = nil, currency: String? = nil) {
        var parameters: [String: Any] = [
            AnalyticsParameterItemID: productID
        ]
        if let value {
            parameters[AnalyticsParameterValue] = NSNumber(value: value)
        }
        if let currency {
            parameters[AnalyticsParameterCurrency] = currency
        }
        logEvent(AnalyticsEventPurchase, parameters: parameters)
    }

    // MARK: - Configuration

    func logConfigurationSaved() {
        logEvent("configuration_saved")
    }

    // MARK: - Radio Activity Tracking

    func startRadioActivity(_ activity: RadioActivityType) {
        guard isAnalyticsEnabled else { return }
        guard activeRadioActivity != activity else { return }

        flushRadioActivityUsage()

        activeRadioActivity = activity
        radioActivityStartTime = Date()

        if activity == .tx {
            logEvent("transmission_started")
        }
    }

    func stopRadioActivity(success: Bool? = nil, failureReason: String? = nil) {
        if let success {
            if success {
                logEvent("transmission_success")
            } else {
                logEvent("transmission_failed", parameters: [
                    AnalyticsParam.reason: failureReason ?? "unknown"
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

        logEvent("radio_activity_usage", parameters: [
            AnalyticsParam.activity: activity.rawValue,
            AnalyticsParam.durationSec: NSNumber(value: duration)
        ])

        activeRadioActivity = nil
        radioActivityStartTime = nil
    }

    // MARK: - Decoded Messages Logic

    func addDecodedMessages(count: Int = 1) {
        sessionDecodedMessages = min(sessionDecodedMessages + count, 10_000)
    }

    func flushDecodedMessages() {
        guard isAnalyticsEnabled, sessionDecodedMessages > 0 else { return }
        logEvent("messages_decoded", parameters: [
            AnalyticsParam.count: NSNumber(value: sessionDecodedMessages)
        ])
        sessionDecodedMessages = 0
    }

    // MARK: - QSO Logic

    func addQSOs(count: Int = 1) {
        sessionQSOs += count
    }

    func flushQSOs() {
        guard isAnalyticsEnabled, sessionQSOs > 0 else { return }
        logEvent("qso_logged", parameters: [
            AnalyticsParam.count: NSNumber(value: sessionQSOs)
        ])
        sessionQSOs = 0
    }

    // MARK: - ADIF Export

    func logADIFExport(qsoCount: Int, exportType: String = "file") {
        logEvent("adif_export", parameters: [
            AnalyticsParam.qsoCount: NSNumber(value: qsoCount),
            AnalyticsParam.exportType: exportType
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
        logEvent(
            AnalyticsEventScreenView,
            parameters: [
                AnalyticsParameterScreenName: screen.rawValue,
                AnalyticsParameterScreenClass: "SwiftUI"
            ]
        )
    }

    func trackViewMode(_ mode: ViewMode) {
        logEvent("view_mode_selected", parameters: [
            AnalyticsParam.viewMode: mode.rawValue.lowercased()
        ])
    }

    func trackRadioModeChange(isFT4: Bool) {
        logEvent("radio_mode_changed", parameters: [
            AnalyticsParam.radioMode: isFT4 ? "ft4" : "ft8"
        ])
    }
}

// MARK: - SwiftUI View Modifier

struct AnalyticsScreenModifier: ViewModifier {
    let screen: AnalyticsScreen

    func body(content: Content) -> some View {
        content
            .onAppear {
                AnalyticsManager.shared.trackScreen(screen)
            }
    }
}

extension View {
    func trackScreen(_ screen: AnalyticsScreen) -> some View {
        modifier(AnalyticsScreenModifier(screen: screen))
    }
}
