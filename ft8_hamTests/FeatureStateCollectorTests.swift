//
//  FeatureStateCollectorTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/11/26.
//

import XCTest
@testable import ft8_ham

/// How settings turn into `feature_state` values.
final class FeatureStateCollectorTests: XCTestCase {

    private typealias Keys = FeatureStateCollector.Keys

    private let suiteName = "FeatureStateCollectorTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func context(
        isPremium: Bool = true,
        flagsOn: Set<FeatureFlag> = Set(FeatureFlag.allCases),
        hasQRZKey: Bool = false,
        hasLoTWCertificate: Bool = false,
        hasEQSLCredentials: Bool = false
    ) -> FeatureStateCollector.Context {
        FeatureStateCollector.Context(
            isPremium: isPremium,
            isFlagEnabled: { flagsOn.contains($0) },
            hasQRZKey: hasQRZKey,
            hasLoTWCertificate: hasLoTWCertificate,
            hasEQSLCredentials: hasEQSLCredentials
        )
    }

    private func states(_ context: FeatureStateCollector.Context? = nil) -> [AnalyticsFeature: FeatureUsageState] {
        FeatureStateCollector.states(defaults: defaults, context: context ?? self.context())
    }

    // MARK: - Untouched settings use their @AppStorage defaults

    func test_untouchedSettings_matchTheirAppStorageDefaults() {
        let states = states()
        XCTAssertEqual(states[.autoSequencing], .on)
        XCTAssertEqual(states[.autoQSOLogging], .on)
        XCTAssertEqual(states[.gpsLocator], .on)
        XCTAssertEqual(states[.catControl], .off)
        XCTAssertEqual(states[.pskReporter], .off)
        XCTAssertEqual(states[.autoCQReply], .off)
        XCTAssertEqual(states[.autoRXAtStart], .off)
        XCTAssertEqual(states[.callAlerts], .off)
        XCTAssertEqual(states[.watchList], .off)
        XCTAssertEqual(states[.activationRefs], .off)
        XCTAssertEqual(states[.cqModifier], .off)
        XCTAssertEqual(states[.holdTXFrequency], .off)
        XCTAssertEqual(states[.heardMe], .on)
    }

    func test_featuresWithoutAState_areNotReported() {
        let states = states()
        XCTAssertNil(states[.statistics])
        XCTAssertNil(states[.iPadDashboard])
        XCTAssertNil(states[.logbookImport])
        XCTAssertNil(states[.qsoEdit])
    }

    func test_switchedOffDefaults_areOff() {
        defaults.set(false, forKey: Keys.autoSequencingEnabled)
        defaults.set(false, forKey: Keys.autoLocatorFromGPS)
        XCTAssertEqual(states()[.autoSequencing], .off)
        XCTAssertEqual(states()[.gpsLocator], .off)
    }

    // MARK: - Log sync

    func test_sync_withoutCredentials_isOff_evenWithAutoUpload() {
        defaults.set(true, forKey: Keys.qrzAutoUpload)
        XCTAssertEqual(states()[.qrzLogbook], .off)
    }

    func test_sync_withCredentials_butNoAutoUpload_isConfigured() {
        let states = states(context(hasQRZKey: true, hasLoTWCertificate: true, hasEQSLCredentials: true))
        XCTAssertEqual(states[.qrzLogbook], .configured)
        XCTAssertEqual(states[.lotwSync], .configured)
        XCTAssertEqual(states[.eqslSync], .configured)
    }

    func test_sync_withCredentialsAndAutoUpload_isOn() {
        defaults.set(true, forKey: Keys.qrzAutoUpload)
        defaults.set(true, forKey: Keys.lotwAutoUpload)
        defaults.set(true, forKey: Keys.eqslAutoUpload)
        let states = states(context(hasQRZKey: true, hasLoTWCertificate: true, hasEQSLCredentials: true))
        XCTAssertEqual(states[.qrzLogbook], .on)
        XCTAssertEqual(states[.lotwSync], .on)
        XCTAssertEqual(states[.eqslSync], .on)
    }

    // MARK: - Premium

    func test_premiumFeatureOn_withoutPremium_isLocked() {
        defaults.set(true, forKey: Keys.catEnabled)
        defaults.set(true, forKey: Keys.pskReporterEnabled)
        let states = states(context(isPremium: false))
        XCTAssertEqual(states[.catControl], .locked)
        XCTAssertEqual(states[.pskReporter], .locked)
    }

    func test_premiumFeatureOn_withPremium_isOn() {
        defaults.set(true, forKey: Keys.catEnabled)
        XCTAssertEqual(states(context(isPremium: true))[.catControl], .on)
    }

    func test_premiumFeatureOffOrConfigured_isNotLocked() {
        let states = states(context(isPremium: false, hasQRZKey: true))
        XCTAssertEqual(states[.catControl], .off)
        XCTAssertEqual(states[.qrzLogbook], .configured)
    }

    func test_freeFeatures_areNeverLocked() {
        XCTAssertEqual(states(context(isPremium: false))[.autoSequencing], .on)
    }

    // MARK: - Remote flags

    func test_flagHiddenPremiumFeatures_areNotReported() {
        defaults.set(true, forKey: Keys.bandHopEnabled)
        defaults.set(true, forKey: Keys.iCloudSyncEnabled)
        defaults.set(true, forKey: Keys.presenceOptIn)
        let states = states(context(flagsOn: []))
        XCTAssertNil(states[.bandHopping])
        XCTAssertNil(states[.iCloudSync])
        XCTAssertNil(states[.presence])
        XCTAssertNil(states[.heardMe])
        XCTAssertEqual(states[.catControl], .off, "Features without a flag are always reported")
    }

    func test_flaggedPremiumFeatures_areReportedWhenTheFlagIsOn() {
        defaults.set(true, forKey: Keys.bandHopEnabled)
        defaults.set(true, forKey: Keys.iCloudSyncEnabled)
        defaults.set(true, forKey: Keys.presenceOptIn)
        let states = states()
        XCTAssertEqual(states[.bandHopping], .on)
        XCTAssertEqual(states[.iCloudSync], .on)
        XCTAssertEqual(states[.presence], .on)
    }

    // MARK: - Composite settings

    func test_callAlerts_isOnWithAnyAlertKind() {
        let keys = [Keys.callAlertSound, Keys.callAlertHaptic, Keys.callAlertNotification]
        for key in keys {
            keys.forEach { defaults.removeObject(forKey: $0) }
            defaults.set(true, forKey: key)
            XCTAssertEqual(states()[.callAlerts], .on, key)
        }
    }

    func test_watchList_needsCallsigns() {
        defaults.set("   ", forKey: Keys.watchedCallsigns)
        XCTAssertEqual(states()[.watchList], .off)

        defaults.set("EA4IQL", forKey: Keys.watchedCallsigns)
        XCTAssertEqual(states()[.watchList], .on)

        defaults.set(false, forKey: Keys.watchAlertEnabled)
        XCTAssertEqual(states()[.watchList], .off)
    }

    func test_activationRefs_isOnWithAnyReference() {
        let keys = [Keys.myPotaRef, Keys.mySotaRef, Keys.myWwffRef, Keys.myIotaRef]
        for key in keys {
            keys.forEach { defaults.removeObject(forKey: $0) }
            defaults.set("REF-0001", forKey: key)
            XCTAssertEqual(states()[.activationRefs], .on, key)
        }
    }

    func test_cqModifier_isOnUnlessNone() {
        defaults.set(CQModifier.none.rawValue, forKey: Keys.cqModifier)
        XCTAssertEqual(states()[.cqModifier], .off)
        defaults.set(CQModifier.dx.rawValue, forKey: Keys.cqModifier)
        XCTAssertEqual(states()[.cqModifier], .on)
    }

    func test_heardMe_followsTheMapLayerSetting() {
        defaults.set(false, forKey: Keys.mapShowHeardMe)
        XCTAssertEqual(states()[.heardMe], .off)
    }

    // MARK: - Map layers

    func test_mapLayers_untouched_matchTheirDefaults() {
        let states = states()
        XCTAssertEqual(states[.mapGrids], .on)
        XCTAssertEqual(states[.mapCountryCircles], .on)
        XCTAssertEqual(states[.mapGeodesics], .on)
        XCTAssertEqual(states[.mapAnnotations], .off)
        XCTAssertEqual(states[.mapPresence], .on)
    }

    func test_mapLayers_followTheirSettings() {
        defaults.set(false, forKey: Keys.mapShowGrids)
        defaults.set(false, forKey: Keys.mapShowCountryCircles)
        defaults.set(false, forKey: Keys.mapShowGeodesics)
        defaults.set(true, forKey: Keys.mapShowAnnotations)
        defaults.set(false, forKey: Keys.mapShowPresence)
        let states = states()
        XCTAssertEqual(states[.mapGrids], .off)
        XCTAssertEqual(states[.mapCountryCircles], .off)
        XCTAssertEqual(states[.mapGeodesics], .off)
        XCTAssertEqual(states[.mapAnnotations], .on)
        XCTAssertEqual(states[.mapPresence], .off)
    }

    func test_mapPresence_hiddenByItsFlag() {
        XCTAssertNil(states(context(flagsOn: []))[.mapPresence])
        XCTAssertEqual(states(context(flagsOn: []))[.mapGrids], .on)
    }

    // MARK: - Replying and filtering

    func test_rxFilter_isOffOnAll_andOnWithAnyFilter() {
        XCTAssertEqual(states()[.rxFilter], .off)

        defaults.set(RXFilterMode.needed.rawValue, forKey: Keys.rxFilterMode)
        XCTAssertEqual(states()[.rxFilter], .on)

        defaults.set(RXFilterMode.all.rawValue, forKey: Keys.rxFilterMode)
        defaults.set(RXFilterMode.mine.rawValue, forKey: Keys.rxFilterModeSeparated)
        XCTAssertEqual(states()[.rxFilter], .on, "The separated layout has its own filter")
    }

    func test_waterfallTapToReply_isOnByDefault() {
        XCTAssertEqual(states()[.waterfallTapToReply], .on)
        defaults.set(false, forKey: Keys.waterfallTapToReply)
        XCTAssertEqual(states()[.waterfallTapToReply], .off)
    }

    func test_replyDoubleTap_isOnOnlyForDouble() {
        XCTAssertEqual(states()[.replyDoubleTap], .off)
        defaults.set(ReplyTapGesture.double.rawValue, forKey: Keys.replyTapGesture)
        XCTAssertEqual(states()[.replyDoubleTap], .on)
        defaults.set(ReplyTapGesture.single.rawValue, forKey: Keys.replyTapGesture)
        XCTAssertEqual(states()[.replyDoubleTap], .off)
    }

    func test_newFreeFeatures_areNeverLocked() {
        defaults.set(RXFilterMode.mine.rawValue, forKey: Keys.rxFilterMode)
        let states = states(context(isPremium: false))
        XCTAssertEqual(states[.rxFilter], .on)
        XCTAssertEqual(states[.mapGrids], .on)
    }

    // MARK: - Current band

    func test_currentBand_defaultsTo10m() {
        XCTAssertEqual(FeatureStateCollector.currentBand(defaults: defaults), .band10m)
    }

    func test_currentBand_readsTheSelectedBand() {
        defaults.set(FT8Message.Band.band40m.rawValue, forKey: Keys.band)
        XCTAssertEqual(FeatureStateCollector.currentBand(defaults: defaults), .band40m)
    }

    func test_currentBand_custom_usesTheDialFrequency() {
        defaults.set(FT8Message.Band.custom.rawValue, forKey: Keys.band)
        XCTAssertEqual(FeatureStateCollector.currentBand(defaults: defaults), .band20m, "Default custom dial is 14.074 MHz")

        defaults.set(7_074_000.0, forKey: Keys.customDialFrequencyHz)
        XCTAssertEqual(FeatureStateCollector.currentBand(defaults: defaults), .band40m)
    }
}
