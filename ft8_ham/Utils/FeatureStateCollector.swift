//
//  FeatureStateCollector.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/11/26.
//

import Foundation

/// Reads whether each feature is switched on, for the `feature_state`
/// snapshot. Settings are read straight from UserDefaults with the same
/// defaults as their `@AppStorage` declarations, so an untouched setting
/// counts as its default and not as off.
enum FeatureStateCollector {

    /// The UserDefaults keys behind the settings, as declared with `@AppStorage`.
    enum Keys {
        static let catEnabled = "catEnabled"
        static let pskReporterEnabled = "pskReporterEnabled"
        static let qrzAutoUpload = "qrzAutoUpload"
        static let lotwAutoUpload = "lotwAutoUpload"
        static let eqslAutoUpload = "eqslAutoUpload"
        static let bandHopEnabled = "bandHopEnabled"
        /// `CloudLogbookSyncManager.enabledKey`
        static let iCloudSyncEnabled = "iCloudLogbookSyncEnabled"
        /// `PresenceManager.optInKey`
        static let presenceOptIn = "presenceOptIn"
        static let autoSequencingEnabled = "autoSequencingEnabled"
        static let autoCQReplyEnabled = "autoCQReplyEnabled"
        static let autoQSOLogging = "autoQSOLogging"
        static let autoRXAtStart = "autoRXAtStart"
        static let callAlertSound = "callAlertSound"
        static let callAlertHaptic = "callAlertHaptic"
        static let callAlertNotification = "callAlertNotification"
        static let watchAlertEnabled = "watchAlertEnabled"
        static let watchedCallsigns = "watchedCallsigns"
        static let autoLocatorFromGPS = "autoLocatorFromGPS"
        static let myPotaRef = "myPotaRef"
        static let mySotaRef = "mySotaRef"
        static let myWwffRef = "myWwffRef"
        static let myIotaRef = "myIotaRef"
        static let cqModifier = "cqModifier"
        static let holdTXFrequency = "holdTXFrequency"
        static let mapShowHeardMe = "mapShowHeardMe"
    }

    /// Everything outside UserDefaults that decides a state.
    struct Context {
        var isPremium: Bool
        var isFlagEnabled: (FeatureFlag) -> Bool
        var hasQRZKey: Bool
        var hasLoTWCertificate: Bool
        var hasEQSLCredentials: Bool
    }

    static func states(defaults: UserDefaults, context: Context) -> [AnalyticsFeature: FeatureUsageState] {
        func bool(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? value
        }
        func isSet(_ key: String) -> Bool {
            !(defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        func onOff(_ isOn: Bool) -> FeatureUsageState { isOn ? .on : .off }
        func sync(autoUpload: String, hasCredentials: Bool) -> FeatureUsageState {
            if !hasCredentials { return .off }
            return bool(autoUpload, default: false) ? .on : .configured
        }

        var states: [AnalyticsFeature: FeatureUsageState] = [
            .catControl: onOff(bool(Keys.catEnabled, default: false)),
            .pskReporter: onOff(bool(Keys.pskReporterEnabled, default: false)),
            .qrzLogbook: sync(autoUpload: Keys.qrzAutoUpload, hasCredentials: context.hasQRZKey),
            .lotwSync: sync(autoUpload: Keys.lotwAutoUpload, hasCredentials: context.hasLoTWCertificate),
            .eqslSync: sync(autoUpload: Keys.eqslAutoUpload, hasCredentials: context.hasEQSLCredentials),
            .bandHopping: onOff(bool(Keys.bandHopEnabled, default: false)),
            .iCloudSync: onOff(bool(Keys.iCloudSyncEnabled, default: false)),
            .presence: onOff(bool(Keys.presenceOptIn, default: false)),

            .autoSequencing: onOff(bool(Keys.autoSequencingEnabled, default: true)),
            .autoCQReply: onOff(bool(Keys.autoCQReplyEnabled, default: false)),
            .autoQSOLogging: onOff(bool(Keys.autoQSOLogging, default: true)),
            .autoRXAtStart: onOff(bool(Keys.autoRXAtStart, default: false)),
            .callAlerts: onOff(
                bool(Keys.callAlertSound, default: false)
                    || bool(Keys.callAlertHaptic, default: false)
                    || bool(Keys.callAlertNotification, default: false)
            ),
            .watchList: onOff(bool(Keys.watchAlertEnabled, default: true) && isSet(Keys.watchedCallsigns)),
            .gpsLocator: onOff(bool(Keys.autoLocatorFromGPS, default: true)),
            .activationRefs: onOff(
                isSet(Keys.myPotaRef) || isSet(Keys.mySotaRef) || isSet(Keys.myWwffRef) || isSet(Keys.myIotaRef)
            ),
            .cqModifier: onOff((defaults.string(forKey: Keys.cqModifier) ?? CQModifier.none.rawValue) != CQModifier.none.rawValue),
            .holdTXFrequency: onOff(bool(Keys.holdTXFrequency, default: false))
        ]

        if context.isFlagEnabled(.enableHeardMe) {
            states[.heardMe] = onOff(bool(Keys.mapShowHeardMe, default: true))
        }

        for (feature, state) in states {
            guard let premium = feature.premiumFeature else { continue }
            // A feature the remote flag hides is not reported at all.
            if let flag = premium.featureFlag, !context.isFlagEnabled(flag) {
                states[feature] = nil
            } else if !context.isPremium, state == .on {
                states[feature] = .locked
            }
        }
        return states
    }

    @MainActor
    static func current() -> [AnalyticsFeature: FeatureUsageState] {
        states(
            defaults: .standard,
            context: Context(
                isPremium: PremiumManager.shared.isPremiumUnlocked,
                isFlagEnabled: { FeatureFlagManager.shared.isEnabled($0) },
                hasQRZKey: PremiumFeatures.qrzService.hasAPIKey,
                hasLoTWCertificate: PremiumFeatures.lotwService.hasCertificate,
                hasEQSLCredentials: PremiumFeatures.eqslService.hasCredentials
            )
        )
    }
}
