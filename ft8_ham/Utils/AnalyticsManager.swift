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
    static let prefix = "prefix"
    // Usage analytics vocabulary. Each one is a GA4 custom dimension, so
    // reuse these before adding a new key.
    static let feature = "feature"
    static let action = "action"
    static let state = "state"
    static let service = "service"
    static let source = "source"
    static let failed = "failed"
    static let errorCode = "error_code"
    static let outcome = "outcome"
}

/// GA4 user properties. Values are at most 36 characters.
enum AnalyticsUserProperty {
    static let isPremium = "is_premium"
}

/// Event names shared by the prompt helpers and their tests.
enum AnalyticsEventName {
    static let ratePromptShown = "rate_prompt_shown"
    static let premiumMomentShown = "premium_moment_shown"
    static let premiumMomentConfirmed = "premium_moment_confirmed"
    static let premiumMomentPostponed = "premium_moment_postponed"
    static let premiumMomentSkipped = "premium_moment_skipped"
}

/// What asked for the App Store rating, sent as `trigger_source` on
/// `rate_prompt_shown`.
enum RatePromptTrigger: String {
    /// The app launch threshold from the prompt config.
    case launches
    /// The QSO threshold behind `rateAfterQSO`.
    case qso
    /// The test button in Debug settings.
    case debug
}

/// The single entry point every event goes through. `AnalyticsManager`
/// sends to Firebase; tests record the calls instead.
protocol AnalyticsLogging: AnyObject {
    func logEvent(_ name: String, parameters: [String: Any]?)
    func setUserProperty(_ value: String?, forName name: String)
}

extension AnalyticsLogging {

    // MARK: - Rate Prompt

    func logRatePromptShown(trigger: RatePromptTrigger) {
        logEvent(AnalyticsEventName.ratePromptShown, parameters: [
            AnalyticsParam.triggerSource: trigger.rawValue
        ])
    }

    // MARK: - Premium Moments

    func logPremiumMomentShown(_ moment: PremiumMoment, appLaunches: Int) {
        logEvent(AnalyticsEventName.premiumMomentShown,
                 parameters: premiumMomentParameters(moment, appLaunches: appLaunches))
    }

    func logPremiumMomentConfirmed(_ moment: PremiumMoment, appLaunches: Int) {
        logEvent(AnalyticsEventName.premiumMomentConfirmed,
                 parameters: premiumMomentParameters(moment, appLaunches: appLaunches))
    }

    func logPremiumMomentPostponed(_ moment: PremiumMoment, appLaunches: Int) {
        logEvent(AnalyticsEventName.premiumMomentPostponed,
                 parameters: premiumMomentParameters(moment, appLaunches: appLaunches))
    }

    func logPremiumMomentSkipped(
        _ moment: PremiumMoment,
        reason: PremiumMomentSkipReason,
        appLaunches: Int,
        roll: Int? = nil
    ) {
        var parameters = premiumMomentParameters(moment, appLaunches: appLaunches)
        parameters[AnalyticsParam.reason] = reason.rawValue
        if let roll {
            parameters[AnalyticsParam.roll] = NSNumber(value: roll)
        }
        logEvent(AnalyticsEventName.premiumMomentSkipped, parameters: parameters)
    }

    private func premiumMomentParameters(_ moment: PremiumMoment, appLaunches: Int) -> [String: Any] {
        [
            AnalyticsParam.triggerSource: moment.rawValue,
            AnalyticsParam.appLaunches: NSNumber(value: appLaunches)
        ]
    }
}

/// Singleton manager to handle anonymous app metrics, App Store compliant.
final class AnalyticsManager: AnalyticsLogging {

    private let appLogger = AppLogger(category: "ANL")

    // MARK: - Singleton
    static let shared = AnalyticsManager()

    // MARK: - Radio Activity State
    private lazy var radioActivity = RadioActivityTracker(logger: self)

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

    func setUserProperty(_ value: String?, forName name: String) {
        guard isAnalyticsEnabled else { return }
        appLogger.debug("Analytics user property: \(name)=\(value ?? "nil")")
        Analytics.setUserProperty(value, forName: name)
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

    func logPurchaseCompleted(productID: String, revenue: PurchaseRevenue) {
        logPurchaseCompleted(productID: productID, value: revenue.value, currency: revenue.currency)
    }

    // MARK: - Errors

    /// Logs a prefix missing from the country table. Only the prefix is sent,
    /// never the full callsign, so the event carries no personal identifier.
    func logCountryNotFound(prefix: String) {
        logEvent("country_not_found", parameters: [AnalyticsParam.prefix: prefix])
    }

    /// The leading prefix of a callsign (`EA4IQL` → `EA4`, `3DA0XYZ` → `3DA0`).
    /// Falls back to the first two characters when the call has no prefix shape.
    static func callsignPrefix(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let range = upper.range(of: "^[0-9]?[A-Z]+[0-9]+", options: .regularExpression) {
            return String(upper[range])
        }
        return String(upper.prefix(2))
    }

    // MARK: - Configuration

    func logConfigurationSaved() {
        logEvent("configuration_saved")
    }

    // MARK: - Radio Activity Tracking

    func startRadioActivity(_ activity: RadioActivityType) {
        guard isAnalyticsEnabled else { return }
        radioActivity.start(activity)
    }

    /// Stops timing RX or TX. `outcome` is reported only if a TX is running.
    func stopRadioActivity(outcome: TransmissionOutcome? = nil) {
        radioActivity.stop(outcome: outcome)
    }

    /// Reports the running TX as failed. Leaves RX timing alone.
    func interruptTransmission(_ reason: TransmissionFailureReason) {
        radioActivity.interruptTransmission(reason)
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
        }
        // Only .background ends radio activity. .inactive (Control Center, a
        // notification banner) leaves the TX audio playing, and it always
        // comes before .background, so stopping here would hide the outcome.
        if scenePhase == .background {
            stopRadioActivity(outcome: .interrupted(.appBackground))
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
