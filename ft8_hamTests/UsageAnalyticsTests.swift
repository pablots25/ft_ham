//
//  UsageAnalyticsTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/11/26.
//

import StoreKit
import XCTest
@testable import ft8_ham

/// The usage analytics recorder: kill switch, de-duplication, counters,
/// CAT sessions, PSK Reporter batches and the feature_state snapshot.
@MainActor
final class UsageAnalyticsTests: XCTestCase {

    private var logger: MockAnalyticsLogger!
    private var defaults: UserDefaults!
    private var clock: Date!
    private var enabled = true
    private var analytics: UsageAnalytics!

    private let suiteName = "UsageAnalyticsTests"

    override func setUp() {
        super.setUp()
        logger = MockAnalyticsLogger()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        enabled = true
        analytics = UsageAnalytics(
            logger: logger,
            isEnabled: { [unowned self] in self.enabled },
            defaults: defaults,
            now: { [unowned self] in self.clock }
        )
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        analytics = nil
        defaults = nil
        logger = nil
        super.tearDown()
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    // MARK: - Kill switch

    func test_disabled_sendsNothing() {
        enabled = false
        analytics.log(.featureAction(.statistics, .opened))
        analytics.setPremium(true)
        analytics.recordServiceError(.qrzLogbook, action: "upload", errorCode: "network")
        analytics.recordUpload(.qrz, success: true)
        analytics.flush()
        analytics.recordFeatureStates([.catControl: .on])

        XCTAssertTrue(logger.events.isEmpty)
        XCTAssertTrue(logger.userProperties.isEmpty)
    }

    func test_disabled_doesNotStoreTheSnapshot_soTheFirstEnabledRunIsDaily() {
        enabled = false
        analytics.recordFeatureStates([.catControl: .on])
        XCTAssertNil(defaults.object(forKey: UsageAnalytics.Keys.lastSnapshotDate))

        enabled = true
        analytics.recordFeatureStates([.catControl: .on])
        XCTAssertEqual(logger.lastEvent?.string(AnalyticsParam.triggerSource), "daily")
    }

    func test_collection_needsTheFlagAndTheUsersConsent() {
        XCTAssertTrue(UsageAnalytics.isCollectionAllowed(flagEnabled: true, userOptedIn: true))
        XCTAssertFalse(UsageAnalytics.isCollectionAllowed(flagEnabled: true, userOptedIn: false))
        XCTAssertFalse(UsageAnalytics.isCollectionAllowed(flagEnabled: false, userOptedIn: true))
        XCTAssertFalse(UsageAnalytics.isCollectionAllowed(flagEnabled: false, userOptedIn: false))
    }

    func test_optedOutUser_turningStatisticsBackOn_getsAFullSnapshot() {
        enabled = false
        analytics.recordFeatureStates([.catControl: .on])
        analytics.setPremium(true)

        enabled = true
        analytics.recordFeatureStates([.catControl: .on])
        analytics.setPremium(true)
        XCTAssertEqual(logger.events(named: "feature_state").count, 1)
        XCTAssertEqual(logger.userProperties[AnalyticsUserProperty.isPremium], "true")
    }

    // MARK: - Privacy

    /// Every value sent must come from a closed set or be a number: no
    /// callsigns, grids, references or free text can slip into an event.
    func test_events_carryOnlyClosedSetValuesAndNumbers() {
        analytics.setPremium(true)
        analytics.recordFeatureStates(FeatureStateCollector.states(
            defaults: defaults,
            context: .init(isPremium: true, isFlagEnabled: { _ in true },
                           hasQRZKey: true, hasLoTWCertificate: true, hasEQSLCredentials: true)
        ))
        analytics.recordAction(.logbookImport, .completed)
        analytics.handle(PremiumServiceEvent(service: .qrz, action: .upload, errorCode: "rejected"))
        analytics.recordServiceError(.iCloudSync, action: "push", error: CloudLogbookSyncError.server("EA4IQL IN85 secret"))
        analytics.recordServiceError(.presence, action: "publish", error: PresenceError.network("host.example.com"))
        analytics.recordUpload(.qrz, success: true)
        analytics.catConnectionChanged(true)
        advance(60)
        analytics.catConnectionChanged(false)
        analytics.flushPSKReporter(sent: 3, failed: 0)
        analytics.flush()

        XCTAssertFalse(logger.events.isEmpty)
        for event in logger.events {
            for (key, value) in event.parameters {
                if value is NSNumber { continue }
                let text = value as? String ?? ""
                XCTAssertNotNil(
                    text.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression),
                    "\(event.name).\(key) = \(text)"
                )
            }
        }
        let everything = logger.events.flatMap { $0.parameters.values.compactMap { $0 as? String } }.joined(separator: " ")
        XCTAssertFalse(everything.contains("EA4IQL"))
        XCTAssertFalse(everything.contains("IN85"))
        XCTAssertFalse(everything.contains("example.com"))
    }

    // MARK: - User properties

    func test_setPremium_setsTheUserPropertyOnlyWhenItChanges() {
        analytics.setPremium(false)
        analytics.setPremium(false)
        XCTAssertEqual(logger.userProperties[AnalyticsUserProperty.isPremium], "false")

        analytics.setPremium(true)
        XCTAssertEqual(logger.userProperties[AnalyticsUserProperty.isPremium], "true")
        XCTAssertEqual(AnalyticsUserProperty.isPremium, "is_premium")
    }

    // MARK: - Feature actions

    func test_recordAction_sendsFeatureAndAction() {
        analytics.recordAction(.bandHopping, .started)
        let event = logger.lastEvent
        XCTAssertEqual(event?.name, "feature_action")
        XCTAssertEqual(event?.string(AnalyticsParam.feature), "band_hopping")
        XCTAssertEqual(event?.string(AnalyticsParam.action), "started")
        XCTAssertNil(event?.parameters[AnalyticsParam.source])
    }

    func test_recordAction_withSource_sendsIt() {
        analytics.recordAction(.statistics, .opened, source: "logbook")
        XCTAssertEqual(logger.lastEvent?.string(AnalyticsParam.source), "logbook")
    }

    func test_recordActionOncePerSession_isResetByFlush() {
        analytics.recordActionOncePerSession(.catControl, .connected)
        analytics.recordActionOncePerSession(.catControl, .connected)
        XCTAssertEqual(logger.events(named: "feature_action").count, 1)

        analytics.flush()
        analytics.recordActionOncePerSession(.catControl, .connected)
        XCTAssertEqual(logger.events(named: "feature_action").count, 2)
    }

    // MARK: - Service errors

    func test_serviceError_isSentOncePerFeatureActionAndCode() {
        analytics.recordServiceError(.presence, action: "publish", errorCode: "network")
        analytics.recordServiceError(.presence, action: "publish", errorCode: "network")
        analytics.recordServiceError(.presence, action: "fetch", errorCode: "network")
        analytics.recordServiceError(.presence, action: "publish", errorCode: "not_available")

        let errors = logger.events(named: "service_error")
        XCTAssertEqual(errors.count, 3)
        XCTAssertEqual(errors.first?.string(AnalyticsParam.feature), "presence")
        XCTAssertEqual(errors.first?.string(AnalyticsParam.action), "publish")
        XCTAssertEqual(errors.first?.string(AnalyticsParam.errorCode), "network")
    }

    func test_serviceError_canRepeatAfterFlush() {
        analytics.recordServiceError(.iCloudSync, action: "push", errorCode: "network")
        analytics.flush()
        analytics.recordServiceError(.iCloudSync, action: "push", errorCode: "network")
        XCTAssertEqual(logger.events(named: "service_error").count, 2)
    }

    func test_serviceError_fromAnError_mapsTheCode() {
        analytics.recordServiceError(.iCloudSync, action: "pull", error: CloudLogbookSyncError.server("boom"))
        XCTAssertEqual(logger.lastEvent?.string(AnalyticsParam.errorCode), "server")
    }

    // MARK: - Premium telemetry

    func test_handle_premiumFailure_sendsServiceError() {
        analytics.handle(PremiumServiceEvent(service: .lotw, action: .upload, errorCode: "signing_failed"))
        let event = logger.lastEvent
        XCTAssertEqual(event?.name, "service_error")
        XCTAssertEqual(event?.string(AnalyticsParam.feature), "lotw_sync")
        XCTAssertEqual(event?.string(AnalyticsParam.action), "upload")
        XCTAssertEqual(event?.string(AnalyticsParam.errorCode), "signing_failed")
    }

    func test_handle_savedCredentials_isConfigured() {
        analytics.handle(PremiumServiceEvent(service: .qrz, action: .saveCredentials))
        analytics.handle(PremiumServiceEvent(service: .lotw, action: .importCertificate))
        let actions = logger.events(named: "feature_action")
        XCTAssertEqual(actions.map { $0.string(AnalyticsParam.feature) }, ["qrz_logbook_sync", "lotw_sync"])
        XCTAssertEqual(actions.map { $0.string(AnalyticsParam.action) }, ["configured", "configured"])
    }

    func test_handle_deletedCredentials_isCleared() {
        analytics.handle(PremiumServiceEvent(service: .eqsl, action: .deleteCredentials))
        analytics.handle(PremiumServiceEvent(service: .lotw, action: .deleteCertificate))
        XCTAssertEqual(
            logger.events(named: "feature_action").map { $0.string(AnalyticsParam.action) },
            ["cleared", "cleared"]
        )
    }

    func test_handle_successfulUploadOrConnect_sendsNothing() {
        analytics.handle(PremiumServiceEvent(service: .qrz, action: .upload))
        analytics.handle(PremiumServiceEvent(service: .cat, action: .connect))
        analytics.handle(PremiumServiceEvent(service: .lotw, action: .fetchConfirmations))
        XCTAssertTrue(logger.events.isEmpty)
    }

    func test_premiumServiceEvent_mapsServicesToFeatures() {
        XCTAssertEqual(PremiumServiceEvent.Service.cat.feature, .catControl)
        XCTAssertEqual(PremiumServiceEvent.Service.qrz.feature, .qrzLogbook)
        XCTAssertEqual(PremiumServiceEvent.Service.lotw.feature, .lotwSync)
        XCTAssertEqual(PremiumServiceEvent.Service.eqsl.feature, .eqslSync)
    }

    /// The adapter maps by raw value, so these must match FTHamPremium.PremiumTelemetryEvent.
    func test_premiumServiceEvent_rawValuesMatchThePremiumPackage() {
        XCTAssertEqual(PremiumServiceEvent.Service.allCases.map(\.rawValue), ["cat", "qrz", "lotw", "eqsl"])
        XCTAssertEqual(
            PremiumServiceEvent.Action.allCases.map(\.rawValue),
            ["connect", "upload", "fetch_confirmations", "save_credentials",
             "delete_credentials", "import_certificate", "delete_certificate"]
        )
    }

    // MARK: - Sync uploads

    func test_uploads_areCountedPerService_andSentOnFlush() {
        analytics.recordUpload(.qrz, success: true)
        analytics.recordUpload(.qrz, success: true)
        analytics.recordUpload(.qrz, success: false)
        analytics.recordUpload(.icloud, success: true, count: 12)
        XCTAssertTrue(logger.events.isEmpty, "Nothing is sent before the flush")

        analytics.flush()
        let uploads = logger.events(named: "sync_upload")
        XCTAssertEqual(uploads.count, 2)

        let qrz = uploads.first { $0.string(AnalyticsParam.service) == "qrz" }
        XCTAssertEqual(qrz?.int(AnalyticsParam.count), 2)
        XCTAssertEqual(qrz?.int(AnalyticsParam.failed), 1)

        let icloud = uploads.first { $0.string(AnalyticsParam.service) == "icloud" }
        XCTAssertEqual(icloud?.int(AnalyticsParam.count), 12)
        XCTAssertEqual(icloud?.int(AnalyticsParam.failed), 0)
    }

    func test_uploads_areClearedByFlush() {
        analytics.recordUpload(.lotw, success: true)
        analytics.flush()
        analytics.flush()
        XCTAssertEqual(logger.events(named: "sync_upload").count, 1)
    }

    func test_uploads_ignoreZeroCounts() {
        analytics.recordUpload(.icloud, success: true, count: 0)
        analytics.flush()
        XCTAssertTrue(logger.events(named: "sync_upload").isEmpty)
    }

    func test_syncService_mapsToItsFeature() {
        XCTAssertEqual(SyncService.qrz.feature, .qrzLogbook)
        XCTAssertEqual(SyncService.lotw.feature, .lotwSync)
        XCTAssertEqual(SyncService.eqsl.feature, .eqslSync)
        XCTAssertEqual(SyncService.icloud.feature, .iCloudSync)
    }

    // MARK: - CAT sessions

    func test_catSession_reportsDurationOnDisconnect() {
        analytics.catConnectionChanged(true)
        advance(125)
        analytics.catConnectionChanged(false)

        let session = logger.events(named: "cat_session")
        XCTAssertEqual(session.count, 1)
        XCTAssertEqual(session.first?.int(AnalyticsParam.durationSec), 125)
        XCTAssertEqual(logger.events(named: "feature_action").first?.string(AnalyticsParam.action), "connected")
    }

    func test_catSession_ignoresVeryShortLinks() {
        analytics.catConnectionChanged(true)
        advance(1)
        analytics.catConnectionChanged(false)
        XCTAssertTrue(logger.events(named: "cat_session").isEmpty)
    }

    func test_catSession_repeatedConnectedSignals_keepTheFirstStart() {
        analytics.catConnectionChanged(true)
        advance(30)
        analytics.catConnectionChanged(true)
        advance(30)
        analytics.catConnectionChanged(false)
        XCTAssertEqual(logger.events(named: "cat_session").first?.int(AnalyticsParam.durationSec), 60)
    }

    func test_catSession_disconnectWithoutConnect_sendsNothing() {
        analytics.catConnectionChanged(false)
        XCTAssertTrue(logger.events.isEmpty)
    }

    func test_catSession_stillConnectedOnFlush_isReportedInPieces() {
        analytics.catConnectionChanged(true)
        advance(100)
        analytics.flush()
        advance(50)
        analytics.catConnectionChanged(false)

        XCTAssertEqual(
            logger.events(named: "cat_session").compactMap { $0.int(AnalyticsParam.durationSec) },
            [100, 50]
        )
    }

    // MARK: - PSK Reporter

    func test_pskReporter_sendsOnlyTheSpotsSinceTheLastFlush() {
        analytics.flushPSKReporter(sent: 40, failed: 2)
        analytics.flushPSKReporter(sent: 55, failed: 2)

        let batches = logger.events(named: "psk_report_batch")
        XCTAssertEqual(batches.compactMap { $0.int(AnalyticsParam.count) }, [40, 15])
        XCTAssertEqual(batches.compactMap { $0.int(AnalyticsParam.failed) }, [2, 0])
    }

    func test_pskReporter_nothingNew_sendsNothing() {
        analytics.flushPSKReporter(sent: 10, failed: 0)
        analytics.flushPSKReporter(sent: 10, failed: 0)
        XCTAssertEqual(logger.events(named: "psk_report_batch").count, 1)
    }

    func test_pskReporter_countersStartingAgain_areTakenFromZero() {
        analytics.flushPSKReporter(sent: 50, failed: 3)
        analytics.flushPSKReporter(sent: 7, failed: 0)
        XCTAssertEqual(logger.events(named: "psk_report_batch").last?.int(AnalyticsParam.count), 7)
    }

    // MARK: - Feature state snapshot

    func test_featureState_firstRun_sendsEveryStateAsDaily() {
        analytics.recordFeatureStates([.catControl: .on, .autoSequencing: .on, .qrzLogbook: .configured])

        let states = logger.events(named: "feature_state")
        XCTAssertEqual(states.count, 3)
        XCTAssertTrue(states.allSatisfy { $0.string(AnalyticsParam.triggerSource) == "daily" })
        let qrz = states.first { $0.string(AnalyticsParam.feature) == "qrz_logbook_sync" }
        XCTAssertEqual(qrz?.string(AnalyticsParam.state), "configured")
    }

    func test_featureState_sameDay_sendsOnlyChanges() {
        analytics.recordFeatureStates([.catControl: .on, .pskReporter: .off])
        logger.reset()
        advance(3600)

        analytics.recordFeatureStates([.catControl: .on, .pskReporter: .on])

        let states = logger.events(named: "feature_state")
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.string(AnalyticsParam.feature), "psk_reporter")
        XCTAssertEqual(states.first?.string(AnalyticsParam.state), "on")
        XCTAssertEqual(states.first?.string(AnalyticsParam.triggerSource), "changed")
    }

    func test_featureState_sameDay_noChanges_sendsNothing() {
        analytics.recordFeatureStates([.catControl: .on])
        logger.reset()
        advance(60)
        analytics.recordFeatureStates([.catControl: .on])
        XCTAssertTrue(logger.events.isEmpty)
    }

    func test_featureState_afterADay_sendsEverythingAgain() {
        analytics.recordFeatureStates([.catControl: .on, .pskReporter: .off])
        logger.reset()
        advance(UsageAnalytics.snapshotInterval)

        analytics.recordFeatureStates([.catControl: .on, .pskReporter: .off])
        let states = logger.events(named: "feature_state")
        XCTAssertEqual(states.count, 2)
        XCTAssertTrue(states.allSatisfy { $0.string(AnalyticsParam.triggerSource) == "daily" })
    }

    func test_featureState_newlyReachableFeature_isSentAsChanged() {
        analytics.recordFeatureStates([.catControl: .on])
        logger.reset()
        advance(60)

        analytics.recordFeatureStates([.catControl: .on, .presence: .on])
        let states = logger.events(named: "feature_state")
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.string(AnalyticsParam.feature), "presence")
        XCTAssertEqual(states.first?.string(AnalyticsParam.triggerSource), "changed")
    }

    func test_featureState_isSentInAStableOrder() {
        analytics.recordFeatureStates([.holdTXFrequency: .off, .catControl: .on, .autoSequencing: .on])
        XCTAssertEqual(
            logger.events(named: "feature_state").compactMap { $0.string(AnalyticsParam.feature) },
            ["cat_control", "auto_sequencing", "hold_tx_frequency"]
        )
    }
}

// MARK: - Event catalog

final class UsageAnalyticsEventTests: XCTestCase {

    func test_names_matchTheCatalog() {
        XCTAssertEqual(UsageAnalyticsEvent.featureState(.catControl, .on, trigger: .daily).name, "feature_state")
        XCTAssertEqual(UsageAnalyticsEvent.featureAction(.statistics, .opened).name, "feature_action")
        XCTAssertEqual(UsageAnalyticsEvent.syncUpload(.qrz, succeeded: 1, failed: 0).name, "sync_upload")
        XCTAssertEqual(UsageAnalyticsEvent.serviceError(.presence, action: "fetch", errorCode: "network").name, "service_error")
        XCTAssertEqual(UsageAnalyticsEvent.catSession(durationSec: 10).name, "cat_session")
        XCTAssertEqual(UsageAnalyticsEvent.pskReportBatch(sent: 1, failed: 0).name, "psk_report_batch")
        XCTAssertEqual(UsageAnalyticsEvent.purchaseStarted(source: "x").name, "purchase_started")
        XCTAssertEqual(UsageAnalyticsEvent.purchaseFailed(source: "x", errorCode: "y").name, "purchase_failed")
        XCTAssertEqual(UsageAnalyticsEvent.paywallDismissed(source: "x", outcome: .closed).name, "paywall_dismissed")
    }

    func test_names_fitFirebaseRules() {
        for name in UsageAnalyticsEvent.Name.all {
            XCTAssertLessThanOrEqual(name.count, 40, name)
            XCTAssertNotNil(name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression), name)
            XCTAssertFalse(name.hasPrefix("firebase_") || name.hasPrefix("google_") || name.hasPrefix("ga_"), name)
        }
        XCTAssertEqual(Set(UsageAnalyticsEvent.Name.all).count, UsageAnalyticsEvent.Name.all.count)
    }

    func test_parameterValues_fitFirebaseRules() {
        let values = AnalyticsFeature.allCases.map(\.rawValue)
            + FeatureUsageState.allCases.map(\.rawValue)
            + FeatureAction.allCases.map(\.rawValue)
            + SyncService.allCases.map(\.rawValue)
            + PaywallOutcome.allCases.map(\.rawValue)
        for value in values {
            XCTAssertLessThanOrEqual(value.count, 100, value)
            XCTAssertNotNil(value.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression), value)
        }
    }

    func test_parameterNames_fitFirebaseRules() {
        let names = [
            AnalyticsParam.feature, AnalyticsParam.action, AnalyticsParam.state,
            AnalyticsParam.service, AnalyticsParam.source, AnalyticsParam.failed,
            AnalyticsParam.errorCode, AnalyticsParam.outcome, AnalyticsParam.count,
            AnalyticsParam.durationSec, AnalyticsParam.triggerSource
        ]
        for name in names {
            XCTAssertLessThanOrEqual(name.count, 40, name)
        }
    }

    func test_featureState_parameters() {
        let parameters = UsageAnalyticsEvent.featureState(.lotwSync, .locked, trigger: .changed).parameters
        XCTAssertEqual(parameters[AnalyticsParam.feature] as? String, "lotw_sync")
        XCTAssertEqual(parameters[AnalyticsParam.state] as? String, "locked")
        XCTAssertEqual(parameters[AnalyticsParam.triggerSource] as? String, "changed")
    }

    func test_purchaseFailed_parameters() {
        let parameters = UsageAnalyticsEvent.purchaseFailed(source: "moment_qso", errorCode: "pending").parameters
        XCTAssertEqual(parameters[AnalyticsParam.source] as? String, "moment_qso")
        XCTAssertEqual(parameters[AnalyticsParam.errorCode] as? String, "pending")
    }

    func test_paywallDismissed_parameters() {
        let parameters = UsageAnalyticsEvent.paywallDismissed(source: "cat_control", outcome: .redeemed).parameters
        XCTAssertEqual(parameters[AnalyticsParam.source] as? String, "cat_control")
        XCTAssertEqual(parameters[AnalyticsParam.outcome] as? String, "redeemed")
    }

    func test_premiumFeatures_shareRawValuesWithPremiumFeature() {
        for premium in PremiumFeature.allCases {
            let feature = AnalyticsFeature(premium)
            XCTAssertEqual(feature.rawValue, premium.rawValue)
            XCTAssertEqual(feature.premiumFeature, premium)
        }
        XCTAssertNil(AnalyticsFeature.autoSequencing.premiumFeature)
    }

    // MARK: - Error codes

    func test_errorCodes_cloudSync() {
        XCTAssertEqual(UsageErrorCode.code(for: CloudLogbookSyncError.premiumRequired), "premium_required")
        XCTAssertEqual(UsageErrorCode.code(for: CloudLogbookSyncError.notAvailable), "not_available")
        XCTAssertEqual(UsageErrorCode.code(for: CloudLogbookSyncError.network("x")), "network")
        XCTAssertEqual(UsageErrorCode.code(for: CloudLogbookSyncError.server("x")), "server")
    }

    func test_errorCodes_presence() {
        XCTAssertEqual(UsageErrorCode.code(for: PresenceError.premiumRequired), "premium_required")
        XCTAssertEqual(UsageErrorCode.code(for: PresenceError.notAvailable), "not_available")
        XCTAssertEqual(UsageErrorCode.code(for: PresenceError.network("x")), "network")
    }

    func test_errorCodes_store() {
        XCTAssertEqual(UsageErrorCode.code(for: PremiumError.userCancelled), "user_cancelled")
        XCTAssertEqual(UsageErrorCode.code(for: PremiumError.pending), "pending")
        XCTAssertEqual(UsageErrorCode.code(for: PremiumError.productNotLoaded), "product_not_loaded")
        XCTAssertEqual(UsageErrorCode.code(for: PremiumError.verificationFailed), "verification_failed")
        XCTAssertEqual(UsageErrorCode.code(for: PremiumError.noPurchaseToRestore), "no_purchase_to_restore")
        XCTAssertEqual(UsageErrorCode.code(for: PremiumError.unknown), "unknown")
        XCTAssertEqual(UsageErrorCode.code(for: StoreKitError.userCancelled as Error), "user_cancelled")
        XCTAssertEqual(UsageErrorCode.code(for: StoreKitError.networkError(URLError(.notConnectedToInternet)) as Error), "store_error")
    }

    func test_errorCodes_genericErrors() {
        XCTAssertEqual(UsageErrorCode.code(for: URLError(.timedOut) as Error), "network")
        XCTAssertEqual(UsageErrorCode.code(for: NSError(domain: "x", code: 1) as Error), "unknown")
        // A typed error passed as `Error` still gets its own code.
        XCTAssertEqual(UsageErrorCode.code(for: PresenceError.notAvailable as Error), "not_available")
    }

    // MARK: - Flag

    func test_usageAnalyticsFlag_isOffInRelease() {
        XCTAssertEqual(FeatureFlag.enableUsageAnalytics.rawValue, "enableUsageAnalytics")
        #if DEBUG
        XCTAssertTrue(FeatureFlag.enableUsageAnalytics.defaultValue)
        #else
        XCTAssertFalse(FeatureFlag.enableUsageAnalytics.defaultValue)
        #endif
    }
}

// MARK: - In-app disclosure

/// The "Share usage statistics" help must match the Privacy Policy, which
/// mentions an app-instance identifier, so it cannot claim no personal data.
final class AnalyticsDisclosureTests: XCTestCase {

    private let languages = ["en", "es", "de", "fr", "it"]

    private func helpText(_ language: String) -> String? {
        let appBundle = Bundle(for: AnalyticsManager.self)
        guard
            let path = appBundle.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return nil }
        let text = bundle.localizedString(forKey: "Analytics help", value: nil, table: nil)
        return text == "Analytics help" ? nil : text
    }

    func test_helpText_existsInEveryLanguage() {
        for language in languages {
            XCTAssertNotNil(helpText(language), language)
        }
    }

    func test_helpText_doesNotClaimNoPersonalData() {
        let forbidden = [
            "en": "No personal data", "es": "ningún dato personal", "de": "keine persönlichen Daten",
            "fr": "Aucune donnée personnelle", "it": "Non vengono raccolti dati personali"
        ]
        for (language, phrase) in forbidden {
            guard let text = helpText(language) else { continue }
            XCTAssertFalse(text.contains(phrase), "\(language): \(text)")
        }
    }

    func test_helpText_namesWhatIsNeverSent() {
        let text = helpText("en") ?? ""
        XCTAssertTrue(text.contains("callsign"), text)
        XCTAssertTrue(text.contains("logbook"), text)
    }
}
