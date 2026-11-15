//
//  RatePromptPolicy.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/11/26.
//

import Foundation

/// Pure decisions behind the App Store rating request, kept out of
/// `InAppPrompts` so they can be unit tested without UserDefaults or UI.
///
/// A rating is requested at most once per major.minor version. Patch
/// releases (1.3.1, 1.3.2) share their minor's request, and the next minor
/// (1.4) may ask again. iOS still decides whether the sheet appears and caps
/// it at three times a year.
enum RatePromptPolicy {

    /// UserDefaults key holding the app version (short version string) of
    /// the last rating request.
    static let lastRequestedVersionKey = "ratePromptLastRequestedVersion"

    /// Major.minor bucket a request belongs to. Versions that cannot be
    /// parsed are their own bucket.
    static func versionBucket(_ version: String) -> String {
        guard let parsed = WhatsNewPolicy.parseMajorMinor(version) else { return version }
        return "\(parsed.major).\(parsed.minor)"
    }

    /// The version of the last request, filling in the running version for
    /// users who were asked before the version was stored (only the legacy
    /// `hasShownRatePrompt` flag is set). Updating to a patch release does
    /// not ask them again, and the next minor version can.
    static func lastRequestedVersion(
        stored: String?,
        legacyRequested: Bool,
        currentVersion: String
    ) -> String? {
        if let stored, !stored.isEmpty { return stored }
        return legacyRequested ? currentVersion : nil
    }

    /// Whether a rating was already requested in the running version's
    /// major.minor.
    static func hasRequested(lastRequestedVersion: String?, currentVersion: String) -> Bool {
        guard let lastRequestedVersion else { return false }
        return versionBucket(lastRequestedVersion) == versionBucket(currentVersion)
    }

    /// Whether this launch should ask for a rating. From the threshold on,
    /// every session rolls again until one passes, so a failed roll on the
    /// threshold launch no longer skips the request forever.
    static func shouldRequestAfterLaunches(
        enabled: Bool,
        alreadyRequested: Bool,
        launches: Int,
        threshold: Int,
        roll: Int,
        probabilityPercent: Int
    ) -> Bool {
        enabled
            && !alreadyRequested
            && launches >= threshold
            && roll <= probabilityPercent
    }
}
