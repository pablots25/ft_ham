//
//  WhatsNewPolicy.swift
//  ft_ham
//

import Foundation

/// Decides what the What's New screen shows and when it appears.
///
/// Two kinds of items live in `whats_new_config`:
/// - Plain items (no `flag`): announced once per major/minor version bump.
/// - Flag-gated items (`flag` set): hidden while their feature flag is off,
///   and announced on their own the first time the flag is on, so a feature
///   enabled from Remote Config mid-version still gets its announcement.
///   An unknown flag name (for example one only a newer build knows) hides
///   the item.
enum WhatsNewPolicy {
    typealias Settings = WhatsNewConfig.WhatsNewSettings
    typealias Item = WhatsNewConfig.WhatsNewSettings.WhatsNewItem

    /// Why the screen should appear, which also decides what it lists.
    enum Trigger: Equatable {
        /// Major/minor bump: every visible item.
        case versionBump
        /// Same version, but flag-gated features turned on: only those.
        case newFeatures(ids: Set<String>)
    }

    // MARK: Filtering

    static func isVisible(_ item: Item, isEnabled: (FeatureFlag) -> Bool) -> Bool {
        guard let flagName = item.flag else { return true }
        guard let flag = FeatureFlag(rawValue: flagName) else { return false }
        return isEnabled(flag)
    }

    /// The settings with every item whose flag is off (or unknown) removed.
    static func visible(_ settings: Settings, isEnabled: (FeatureFlag) -> Bool) -> Settings {
        Settings(
            enabled: settings.enabled,
            features: settings.features.filter { isVisible($0, isEnabled: isEnabled) },
            improvements: settings.improvements.filter { isVisible($0, isEnabled: isEnabled) },
            bugFixes: settings.bugFixes.filter { isVisible($0, isEnabled: isEnabled) }
        )
    }

    /// Only the items whose id is in `ids`.
    static func restricted(_ settings: Settings, to ids: Set<String>) -> Settings {
        Settings(
            enabled: settings.enabled,
            features: settings.features.filter { ids.contains($0.id) },
            improvements: settings.improvements.filter { ids.contains($0.id) },
            bugFixes: settings.bugFixes.filter { ids.contains($0.id) }
        )
    }

    static func allItems(_ settings: Settings) -> [Item] {
        settings.features + settings.improvements + settings.bugFixes
    }

    /// Ids of the visible flag-gated items, the ones tracked as "seen".
    static func flaggedIDs(_ visibleSettings: Settings) -> Set<String> {
        Set(allItems(visibleSettings).filter { $0.flag != nil }.map(\.id))
    }

    // MARK: Trigger

    /// - Parameters:
    ///   - lastSeenVersion: short version stored when the user last closed
    ///     the screen (or the install baseline). Empty means unknown.
    ///   - seenFlaggedIDs: flag-gated item ids already announced.
    static func trigger(
        settings: Settings,
        currentVersion: String,
        lastSeenVersion: String,
        seenFlaggedIDs: Set<String>,
        isEnabled: (FeatureFlag) -> Bool
    ) -> Trigger? {
        guard settings.enabled, !lastSeenVersion.isEmpty else { return nil }

        let visibleSettings = visible(settings, isEnabled: isEnabled)
        guard !allItems(visibleSettings).isEmpty else { return nil }

        if isMajorOrMinorBump(from: lastSeenVersion, to: currentVersion) {
            return .versionBump
        }

        let unseen = flaggedIDs(visibleSettings).subtracting(seenFlaggedIDs)
        return unseen.isEmpty ? nil : .newFeatures(ids: unseen)
    }

    // MARK: Versions

    static func isMajorOrMinorBump(from last: String, to current: String) -> Bool {
        if let currentMM = parseMajorMinor(current), let lastMM = parseMajorMinor(last) {
            if currentMM.major != lastMM.major { return currentMM.major > lastMM.major }
            return currentMM.minor > lastMM.minor
        }
        // Unparseable versions: fall back to any change.
        return current != last
    }

    static func parseMajorMinor(_ version: String) -> (major: Int, minor: Int)? {
        let parts = version
            .split(whereSeparator: { $0 == "." || $0 == "-" })
            .compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }
}
