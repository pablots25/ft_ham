//
//  UsageAnalytics.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/11/26.
//

import Combine
import Foundation
import SwiftUI

/// Records how features are used: which are switched on, what users do with
/// them and how the services behind them perform. Everything goes through
/// `log(_:)`, which drops events while `enableUsageAnalytics` is off.
///
/// Volume rules: nothing is sent per FT8/FT4 cycle. Uploads and PSK Reporter
/// spots are counted and sent when the app goes to the background, and each
/// service error is sent once per session.
@MainActor
final class UsageAnalytics {

    static let shared = UsageAnalytics(
        logger: AnalyticsManager.shared,
        isEnabled: { FeatureFlagManager.shared.isEnabled(.enableUsageAnalytics) }
    )

    /// Time between two daily `feature_state` snapshots.
    static let snapshotInterval: TimeInterval = 24 * 60 * 60
    /// CAT sessions shorter than this are not reported.
    static let minimumCATSessionSeconds = 3

    enum Keys {
        static let lastSnapshotDate = "usageAnalytics.lastSnapshotDate"
        static let lastFeatureStates = "usageAnalytics.lastFeatureStates"
    }

    private let logger: AnalyticsLogging
    private let isEnabled: @MainActor () -> Bool
    private let defaults: UserDefaults
    private let now: () -> Date

    // Session state, reset by `flush()`.
    private var uploads: [SyncService: (succeeded: Int, failed: Int)] = [:]
    private var reportedErrors: Set<String> = []
    private var reportedActions: Set<String> = []

    // Long-lived counters.
    private var catConnectedAt: Date?
    private var pskBaseline: (sent: Int, failed: Int) = (0, 0)
    private var lastPremium: Bool?

    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    init(
        logger: AnalyticsLogging,
        isEnabled: @escaping @MainActor () -> Bool,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.logger = logger
        self.isEnabled = isEnabled
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Sending

    func log(_ event: UsageAnalyticsEvent) {
        guard isEnabled() else { return }
        logger.logEvent(event.name, parameters: event.parameters)
    }

    // MARK: - User properties

    func setPremium(_ isPremium: Bool) {
        guard isEnabled(), lastPremium != isPremium else { return }
        lastPremium = isPremium
        logger.setUserProperty(isPremium ? "true" : "false", forName: AnalyticsUserProperty.isPremium)
    }

    // MARK: - Feature actions

    func recordAction(_ feature: AnalyticsFeature, _ action: FeatureAction, source: String? = nil) {
        log(.featureAction(feature, action, source: source))
    }

    /// Like `recordAction`, but at most once per session (e.g. CAT
    /// reconnecting on its own after a dropout).
    func recordActionOncePerSession(_ feature: AnalyticsFeature, _ action: FeatureAction) {
        let key = "\(feature.rawValue)|\(action.rawValue)"
        guard isEnabled(), !reportedActions.contains(key) else { return }
        reportedActions.insert(key)
        recordAction(feature, action)
    }

    // MARK: - Service errors

    /// Sends `service_error` once per feature, action and code each session.
    func recordServiceError(_ feature: AnalyticsFeature, action: String, errorCode: String) {
        let key = "\(feature.rawValue)|\(action)|\(errorCode)"
        guard isEnabled(), !reportedErrors.contains(key) else { return }
        reportedErrors.insert(key)
        log(.serviceError(feature, action: action, errorCode: errorCode))
    }

    func recordServiceError(_ feature: AnalyticsFeature, action: String, error: Error) {
        recordServiceError(feature, action: action, errorCode: UsageErrorCode.code(for: error))
    }

    /// Something a premium service reported through `PremiumFeatures.installTelemetry`.
    func handle(_ event: PremiumServiceEvent) {
        if let errorCode = event.errorCode {
            recordServiceError(event.service.feature, action: event.action.rawValue, errorCode: errorCode)
            return
        }
        switch event.action {
        case .saveCredentials, .importCertificate:
            recordAction(event.service.feature, .configured)
        case .deleteCredentials, .deleteCertificate:
            recordAction(event.service.feature, .cleared)
        case .connect, .upload, .fetchConfirmations:
            // Successes are counted elsewhere (sync_upload, cat_session).
            break
        }
    }

    // MARK: - Sync uploads

    func recordUpload(_ service: SyncService, success: Bool, count: Int = 1) {
        guard count > 0 else { return }
        var totals = uploads[service] ?? (0, 0)
        if success {
            totals.succeeded += count
        } else {
            totals.failed += count
        }
        uploads[service] = totals
    }

    // MARK: - CAT

    func catConnectionChanged(_ connected: Bool) {
        if connected {
            guard catConnectedAt == nil else { return }
            catConnectedAt = now()
            recordActionOncePerSession(.catControl, .connected)
        } else {
            endCATSession()
        }
    }

    private func endCATSession(continuing: Bool = false) {
        guard let start = catConnectedAt else { return }
        let end = now()
        catConnectedAt = continuing ? end : nil
        let seconds = Int(end.timeIntervalSince(start))
        guard seconds >= Self.minimumCATSessionSeconds else { return }
        log(.catSession(durationSec: seconds))
    }

    // MARK: - PSK Reporter

    /// Sends the spots reported since the last call. `sent` and `failed` are
    /// the reporter's running totals for this launch.
    func flushPSKReporter(sent: Int, failed: Int) {
        // The reporter's counters start again at zero on each launch.
        if sent < pskBaseline.sent || failed < pskBaseline.failed {
            pskBaseline = (0, 0)
        }
        let newSent = sent - pskBaseline.sent
        let newFailed = failed - pskBaseline.failed
        pskBaseline = (sent, failed)
        guard newSent > 0 || newFailed > 0 else { return }
        log(.pskReportBatch(sent: newSent, failed: newFailed))
    }

    // MARK: - Feature state

    /// Sends every state once a day, and in between only the ones that
    /// changed since the last send.
    func recordFeatureStates(_ states: [AnalyticsFeature: FeatureUsageState]) {
        guard isEnabled() else { return }

        let previous = defaults.dictionary(forKey: Keys.lastFeatureStates) as? [String: String] ?? [:]
        let lastSnapshot = defaults.object(forKey: Keys.lastSnapshotDate) as? Date
        let current = now()
        let isDue = lastSnapshot.map { current.timeIntervalSince($0) >= Self.snapshotInterval } ?? true

        for feature in AnalyticsFeature.allCases {
            guard let state = states[feature] else { continue }
            if isDue {
                log(.featureState(feature, state, trigger: .daily))
            } else if let old = previous[feature.rawValue], old != state.rawValue {
                log(.featureState(feature, state, trigger: .changed))
            } else if previous[feature.rawValue] == nil {
                // A feature that became reachable since the last snapshot.
                log(.featureState(feature, state, trigger: .changed))
            }
        }

        defaults.set(
            Dictionary(uniqueKeysWithValues: states.map { ($0.key.rawValue, $0.value.rawValue) }),
            forKey: Keys.lastFeatureStates
        )
        if isDue {
            defaults.set(current, forKey: Keys.lastSnapshotDate)
        }
    }

    // MARK: - Flush

    /// Sends the session's counters. Called when the app leaves the foreground.
    func flush() {
        for service in SyncService.allCases {
            guard let totals = uploads[service], totals.succeeded + totals.failed > 0 else { continue }
            log(.syncUpload(service, succeeded: totals.succeeded, failed: totals.failed))
        }
        uploads.removeAll()
        // A CAT link that stays up in the background is reported in pieces.
        endCATSession(continuing: true)
        reportedErrors.removeAll()
        reportedActions.removeAll()
    }
}

// MARK: - App wiring

extension UsageAnalytics {

    /// Hooks premium telemetry and the Premium entitlement. Safe to call
    /// more than once.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        PremiumFeatures.installTelemetry { [weak self] event in
            self?.handle(event)
        }
        PremiumManager.shared.$isPremiumUnlocked
            .removeDuplicates()
            .sink { [weak self] isPremium in self?.setPremium(isPremium) }
            .store(in: &cancellables)
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            start()
            setPremium(PremiumManager.shared.isPremiumUnlocked)
            recordFeatureStates(FeatureStateCollector.current())
        case .background:
            recordFeatureStates(FeatureStateCollector.current())
            let stats = PremiumFeatures.pskReporter.stats
            flushPSKReporter(sent: stats.sent, failed: stats.errors)
            flush()
        default:
            break
        }
    }
}
