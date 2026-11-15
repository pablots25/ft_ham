//
//  UsageAnalyticsEvent.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/11/26.
//

import Foundation
import StoreKit

// MARK: - Vocabulary

/// Everything usage analytics can talk about, free and premium. Raw values
/// are the `feature` parameter. Premium ones match `PremiumFeature` so the
/// paywall `source` and the usage events line up in reports.
enum AnalyticsFeature: String, CaseIterable {
    // Premium
    case catControl = "cat_control"
    case pskReporter = "psk_reporter"
    case qrzLogbook = "qrz_logbook_sync"
    case lotwSync = "lotw_sync"
    case eqslSync = "eqsl_sync"
    case statistics
    case bandHopping = "band_hopping"
    case iCloudSync = "icloud_sync"
    case presence
    case iPadDashboard = "ipad_dashboard"
    // Free
    case autoSequencing = "auto_sequencing"
    case autoCQReply = "auto_cq_reply"
    case autoQSOLogging = "auto_qso_logging"
    case autoRXAtStart = "auto_rx_at_start"
    case callAlerts = "call_alerts"
    case watchList = "watch_list"
    case gpsLocator = "gps_locator"
    case activationRefs = "activation_refs"
    case cqModifier = "cq_modifier"
    case holdTXFrequency = "hold_tx_frequency"
    case heardMe = "heard_me"
    case logbookImport = "logbook_import"
    case qsoEdit = "qso_edit"
    case freeTextTX = "free_text_tx"
    /// The band in use. The band itself goes in `source`.
    case band
    /// Deleting, searching and filtering the logbook.
    case logbook
    case mapGrids = "map_grids"
    case mapCountryCircles = "map_country_circles"
    case mapGeodesics = "map_geodesics"
    case mapAnnotations = "map_annotations"
    case mapPresence = "map_presence"
    /// The RX list filter. The mode goes in `source`.
    case rxFilter = "rx_filter"
    case waterfallTapToReply = "waterfall_tap_to_reply"
    case replyDoubleTap = "reply_double_tap"
    case tutorials

    init(_ premium: PremiumFeature) {
        switch premium {
        case .catControl: self = .catControl
        case .pskReporter: self = .pskReporter
        case .qrzLogbook: self = .qrzLogbook
        case .lotwSync: self = .lotwSync
        case .eqslSync: self = .eqslSync
        case .statistics: self = .statistics
        case .bandHopping: self = .bandHopping
        case .iCloudSync: self = .iCloudSync
        case .presence: self = .presence
        case .iPadDashboard: self = .iPadDashboard
        }
    }

    /// The premium feature behind this one, if any.
    var premiumFeature: PremiumFeature? {
        PremiumFeature(rawValue: rawValue)
    }
}

/// The `state` parameter of `feature_state`.
enum FeatureUsageState: String, CaseIterable {
    /// Switched off.
    case off
    /// Switched on and usable.
    case on
    /// Credentials are set up but the feature itself is switched off.
    case configured
    /// Switched on, but the user has no Premium, so it does nothing.
    case locked
}

/// Why a `feature_state` event was sent (`trigger_source`).
enum FeatureStateTrigger: String {
    /// The once-a-day snapshot.
    case daily
    /// The state differs from the last one sent.
    case changed
}

/// The `action` parameter of `feature_action`.
enum FeatureAction: String, CaseIterable {
    case opened
    case started
    case stopped
    case configured
    case cleared
    case connected
    case completed
    /// A band, mode or setting picked from a list (value in `source`).
    case selected
    /// The band was in use during this session (band in `source`).
    case used
    case deleted
    /// A delete was undone.
    case restored
    case searched
    case filtered
    /// Band hopping moved to another band on its own.
    case hopped
    /// The user skipped to the next band hop.
    case skipped
    /// QSOs confirmed by a log service (`count`).
    case confirmed
    /// QSOs from another device merged into the logbook (`count`).
    case merged
    /// The whole logbook uploaded by hand (`count`).
    case uploadedAll = "uploaded_all"
    /// Help messages or the onboarding shown again.
    case reset
    /// Other operators seen on the air this session (`count`, the most at once).
    case seen
}

/// Services whose uploads are counted in `sync_upload`.
enum SyncService: String, CaseIterable {
    case qrz
    case lotw
    case eqsl
    case icloud

    var feature: AnalyticsFeature {
        switch self {
        case .qrz: return .qrzLogbook
        case .lotw: return .lotwSync
        case .eqsl: return .eqslSync
        case .icloud: return .iCloudSync
        }
    }
}

/// How the paywall closed (`outcome` on `paywall_dismissed`).
enum PaywallOutcome: String, CaseIterable {
    case purchased
    case restored
    /// Unlocked by an offer code while the paywall was open.
    case redeemed
    case closed
}

/// Coarse error codes the app itself produces. Premium services send their
/// own (see `PremiumServiceEvent`), drawn from the same style.
enum UsageErrorCode {
    static let premiumRequired = "premium_required"
    static let notAvailable = "not_available"
    static let network = "network"
    static let server = "server"
    static let commandFailed = "command_failed"
    static let userCancelled = "user_cancelled"
    static let pending = "pending"
    static let productNotLoaded = "product_not_loaded"
    static let verificationFailed = "verification_failed"
    static let noPurchaseToRestore = "no_purchase_to_restore"
    static let storeError = "store_error"
    static let unknown = "unknown"

    static func code(for error: CloudLogbookSyncError) -> String {
        switch error {
        case .premiumRequired: return premiumRequired
        case .notAvailable: return notAvailable
        case .network: return network
        case .server: return server
        }
    }

    static func code(for error: PresenceError) -> String {
        switch error {
        case .premiumRequired: return premiumRequired
        case .notAvailable: return notAvailable
        case .network: return network
        }
    }

    static func code(for error: PremiumError) -> String {
        switch error {
        case .productNotLoaded: return productNotLoaded
        case .userCancelled: return userCancelled
        case .pending: return pending
        case .verificationFailed: return verificationFailed
        case .noPurchaseToRestore: return noPurchaseToRestore
        case .unknown: return unknown
        }
    }

    /// Any error thrown by iCloud sync, presence or the store.
    static func code(for error: Error) -> String {
        if let error = error as? CloudLogbookSyncError { return code(for: error) }
        if let error = error as? PresenceError { return code(for: error) }
        if let error = error as? PremiumError { return code(for: error) }
        if let error = error as? StoreKitError {
            if case .userCancelled = error { return userCancelled }
            return storeError
        }
        if error is URLError { return network }
        return unknown
    }
}

/// Reads how many QSOs a confirmation fetch returned. QRZ answers with a
/// plain number, LoTW and eQSL with an ADIF report (one `<eor>` per QSO).
enum ConfirmationCounter {
    static func count(in response: String?) -> Int {
        guard let response = response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else { return 0 }
        if let number = Int(response) { return max(number, 0) }
        return response.lowercased().components(separatedBy: "<eor>").count - 1
    }
}

// MARK: - Events

/// Every usage event, typed. `name` and `parameters` are the only place the
/// wire format is written, so tests can check it without Firebase.
enum UsageAnalyticsEvent: Equatable {
    case featureState(AnalyticsFeature, FeatureUsageState, trigger: FeatureStateTrigger)
    case featureAction(AnalyticsFeature, FeatureAction, source: String? = nil, count: Int? = nil)
    case syncUpload(SyncService, succeeded: Int, failed: Int)
    case serviceError(AnalyticsFeature, action: String, errorCode: String)
    case catSession(durationSec: Int)
    case pskReportBatch(sent: Int, failed: Int)
    case purchaseStarted(source: String)
    case purchaseFailed(source: String, errorCode: String)
    case paywallDismissed(source: String, outcome: PaywallOutcome)

    enum Name {
        static let featureState = "feature_state"
        static let featureAction = "feature_action"
        static let syncUpload = "sync_upload"
        static let serviceError = "service_error"
        static let catSession = "cat_session"
        static let pskReportBatch = "psk_report_batch"
        static let purchaseStarted = "purchase_started"
        static let purchaseFailed = "purchase_failed"
        static let paywallDismissed = "paywall_dismissed"

        static let all = [
            featureState, featureAction, syncUpload, serviceError, catSession,
            pskReportBatch, purchaseStarted, purchaseFailed, paywallDismissed
        ]
    }

    var name: String {
        switch self {
        case .featureState: return Name.featureState
        case .featureAction: return Name.featureAction
        case .syncUpload: return Name.syncUpload
        case .serviceError: return Name.serviceError
        case .catSession: return Name.catSession
        case .pskReportBatch: return Name.pskReportBatch
        case .purchaseStarted: return Name.purchaseStarted
        case .purchaseFailed: return Name.purchaseFailed
        case .paywallDismissed: return Name.paywallDismissed
        }
    }

    var parameters: [String: Any] {
        switch self {
        case let .featureState(feature, state, trigger):
            return [
                AnalyticsParam.feature: feature.rawValue,
                AnalyticsParam.state: state.rawValue,
                AnalyticsParam.triggerSource: trigger.rawValue
            ]
        case let .featureAction(feature, action, source, count):
            var parameters: [String: Any] = [
                AnalyticsParam.feature: feature.rawValue,
                AnalyticsParam.action: action.rawValue
            ]
            if let source { parameters[AnalyticsParam.source] = source }
            if let count { parameters[AnalyticsParam.count] = NSNumber(value: count) }
            return parameters
        case let .syncUpload(service, succeeded, failed):
            return [
                AnalyticsParam.service: service.rawValue,
                AnalyticsParam.count: NSNumber(value: succeeded),
                AnalyticsParam.failed: NSNumber(value: failed)
            ]
        case let .serviceError(feature, action, errorCode):
            return [
                AnalyticsParam.feature: feature.rawValue,
                AnalyticsParam.action: action,
                AnalyticsParam.errorCode: errorCode
            ]
        case let .catSession(durationSec):
            return [AnalyticsParam.durationSec: NSNumber(value: durationSec)]
        case let .pskReportBatch(sent, failed):
            return [
                AnalyticsParam.count: NSNumber(value: sent),
                AnalyticsParam.failed: NSNumber(value: failed)
            ]
        case let .purchaseStarted(source):
            return [AnalyticsParam.source: source]
        case let .purchaseFailed(source, errorCode):
            return [
                AnalyticsParam.source: source,
                AnalyticsParam.errorCode: errorCode
            ]
        case let .paywallDismissed(source, outcome):
            return [
                AnalyticsParam.source: source,
                AnalyticsParam.outcome: outcome.rawValue
            ]
        }
    }
}
