//
//  AppVersionManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/02/26.
//

import Foundation

/// Tracks which version and which flag-gated features the user has already
/// been told about. The rules themselves live in `WhatsNewPolicy`.
@MainActor
final class AppVersionManager {
    static let shared = AppVersionManager()

    enum Keys {
        static let lastSeenAppVersion = "lastSeenAppVersion"
        static let hasSeenWhatsNew = "hasSeenWhatsNew"
        static let seenFlaggedItemIDs = "whatsNewSeenFlaggedItemIDs"
    }

    private let defaults: UserDefaults
    private let shortVersionProvider: () -> String
    private let settingsProvider: () -> WhatsNewConfig.WhatsNewSettings
    private let flagResolver: (FeatureFlag) -> Bool

    private convenience init() {
        let remoteConfig = RemoteConfigProvider()
        self.init(
            defaults: .standard,
            shortVersion: { Bundle.main.shortVersion },
            settings: { remoteConfig.getWhatsNewConfig().whatsNew },
            isEnabled: { flag in
                #if DEBUG
                // Debug builds follow the Debug screen, like the rest of the app.
                return FeatureFlagManager.shared.isEnabled(flag)
                #else
                // Read the activated Remote Config value directly. At launch
                // FeatureFlagManager still holds compiled-in defaults until its
                // first fetch completes, which would hide every gated item.
                return remoteConfig.boolValue(for: flag)
                #endif
            }
        )
    }

    init(
        defaults: UserDefaults,
        shortVersion: @escaping () -> String,
        settings: @escaping () -> WhatsNewConfig.WhatsNewSettings,
        isEnabled: @escaping (FeatureFlag) -> Bool
    ) {
        self.defaults = defaults
        self.shortVersionProvider = shortVersion
        self.settingsProvider = settings
        self.flagResolver = isEnabled
    }

    var currentVersion: String {
        Bundle.main.appVersion
    }

    private var lastSeenAppVersion: String {
        get { defaults.string(forKey: Keys.lastSeenAppVersion) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastSeenAppVersion) }
    }

    private var seenFlaggedItemIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.seenFlaggedItemIDs) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Keys.seenFlaggedItemIDs) }
    }

    private var visibleSettings: WhatsNewConfig.WhatsNewSettings {
        WhatsNewPolicy.visible(settingsProvider(), isEnabled: flagResolver)
    }

    /// Why What's New should appear now, or nil.
    var whatsNewTrigger: WhatsNewPolicy.Trigger? {
        WhatsNewPolicy.trigger(
            settings: settingsProvider(),
            currentVersion: shortVersionProvider(),
            lastSeenVersion: lastSeenAppVersion,
            seenFlaggedIDs: seenFlaggedItemIDs,
            isEnabled: flagResolver
        )
    }

    var shouldShowWhatsNew: Bool {
        whatsNewTrigger != nil
    }

    /// What the screen lists: only the newly enabled features when that is
    /// why it opened, otherwise every visible item. Nil when disabled.
    var whatsNewContent: WhatsNewConfig.WhatsNewSettings? {
        let settings = visibleSettings
        guard settings.enabled else { return nil }
        if case .newFeatures(let ids) = whatsNewTrigger {
            return WhatsNewPolicy.restricted(settings, to: ids)
        }
        return settings
    }

    /// Records the current version the first time the app runs with no stored
    /// version, so the next major/minor update can be announced. Without it a
    /// fresh install never had a baseline and What's New could never appear.
    /// Flag-gated items already on are marked seen: a new user does not need
    /// an announcement for features that were there from the start.
    func recordInstallBaselineIfNeeded() {
        guard lastSeenAppVersion.isEmpty else { return }
        lastSeenAppVersion = shortVersionProvider()
        seenFlaggedItemIDs.formUnion(WhatsNewPolicy.flaggedIDs(visibleSettings))
    }

    func markWhatsNewAsViewed() {
        lastSeenAppVersion = shortVersionProvider()
        seenFlaggedItemIDs.formUnion(WhatsNewPolicy.flaggedIDs(visibleSettings))
        defaults.set(true, forKey: Keys.hasSeenWhatsNew)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version).\(build)"
    }

    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
