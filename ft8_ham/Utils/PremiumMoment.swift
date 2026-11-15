//
//  PremiumMoment.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/11/26.
//

import Foundation

/// A point in normal use where a free user has just done something a
/// Premium feature makes easier. Each moment names that feature, so the
/// prompt talks about what the user is doing right now instead of asking
/// for a tip.
enum PremiumMoment: String, Identifiable, CaseIterable {
    /// A QSO was logged. Premium uploads it to LoTW, QRZ and eQSL.
    case qsoLogged = "qso"
    /// The logbook was exported to ADIF. Premium syncs it without exporting.
    case adifExport = "adif"
    /// A transmission started. Premium reports to PSK Reporter.
    case txStarted = "tx"

    var id: String { rawValue }

    /// The Premium feature that answers this moment.
    var feature: PremiumFeature {
        switch self {
        case .qsoLogged: return .lotwSync
        case .adifExport: return .qrzLogbook
        case .txStarted: return .pskReporter
        }
    }

    /// Paywall attribution, kept apart from locked rows and screens.
    var paywallSource: PaywallSource { .screen("moment_\(rawValue)") }

    var title: String {
        switch self {
        case .qsoLogged: return String(localized: "Confirm QSOs on LoTW?")
        case .adifExport: return String(localized: "Skip the export next time?")
        case .txStarted: return String(localized: "Where is your signal heard?")
        }
    }

    var message: String {
        switch self {
        case .qsoLogged:
            return String(localized: "Premium uploads every QSO to LoTW, QRZ and eQSL as you log it.")
        case .adifExport:
            return String(localized: "Premium sends your QSOs to QRZ, LoTW and eQSL automatically.")
        case .txStarted:
            return String(localized: "Premium reports to PSK Reporter so you can see where your signal is received.")
        }
    }
}

/// Why a milestone did not raise its Premium prompt, sent as `reason` on
/// `premium_moment_skipped`.
enum PremiumMomentSkipReason: String, CaseIterable {
    /// The user already has Premium.
    case isPremium = "is_premium"
    /// Another prompt already showed this session.
    case promptPresentedThisSession = "prompt_presented_this_session"
    /// The share sheet is on screen.
    case shareSheetActive = "share_sheet_active"
    /// Too few launches since the last milestone prompt.
    case cooldown
    /// The threshold was reached but the probability roll failed.
    case probabilityRoll = "probability_roll"
}

/// Pure decisions behind the usage-milestone prompts, kept out of
/// `InAppPrompts` so they can be unit tested without UserDefaults or UI.
enum PromptMomentPolicy {

    /// QSOs to log before asking for a rating when `rateAfterQSO` is on.
    /// Low on purpose: a completed QSO is the happiest moment in the app.
    static let reviewQSOThreshold = 3

    /// Whether a usage milestone should offer Premium instead of a tip.
    static func offersPremium(flagEnabled: Bool, isPremium: Bool) -> Bool {
        flagEnabled && !isPremium
    }

    /// The reason a milestone stops before counting toward its threshold,
    /// or nil when it goes on to the cooldown and threshold checks.
    static func premiumMomentSkipReason(
        isPremium: Bool,
        presentedThisSession: Bool,
        shareSheetActive: Bool
    ) -> PremiumMomentSkipReason? {
        if isPremium { return .isPremium }
        if presentedThisSession { return .promptPresentedThisSession }
        if shareSheetActive { return .shareSheetActive }
        return nil
    }

    /// Whether logging the QSO number `qsoCount` should ask for a rating.
    /// Fires from the threshold QSO on (a later QSO if another prompt took
    /// that session), and never again once a rating was requested.
    static func shouldRequestReviewAfterQSO(
        flagEnabled: Bool,
        ratePromptEnabled: Bool,
        alreadyRequested: Bool,
        presentedThisSession: Bool,
        qsoCount: Int,
        threshold: Int = reviewQSOThreshold
    ) -> Bool {
        flagEnabled
            && ratePromptEnabled
            && !alreadyRequested
            && !presentedThisSession
            && qsoCount >= threshold
    }
}
