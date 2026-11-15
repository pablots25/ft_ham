//
//  FeatureFlag.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/02/26.
//

import Foundation

enum FeatureFlag: String, CaseIterable {
    case showLogsView
    case backgroundToast
    case enableIpadDashboard
    /// "Quick config" sheet opened from the message selector.
    case controlsSheet
    /// The grouped, searchable Configuration screen. On by default: it is
    /// live for everyone, and a device that never reaches Remote Config (a DNS
    /// filter, no network at launch) would otherwise stay on the old screen.
    /// Turning it off remotely still brings the old screen back.
    case newConfigView
    case donationsEnabled
    /// Free-text (type 0.0) transmission loop.
    case enableFreeText
    /// Premium: autonomous band hopping over CAT.
    case enableBandHopping
    /// Premium: iCloud logbook sync.
    case enableICloudSync
    /// Premium: "users online" presence on the map.
    case enablePresence
    /// Waterfall: even/odd slot stripe and greyed-out transmit rows.
    case waterfallSlotContext
    /// Map: "heard me" layer (stations that decoded us, from PSK Reporter).
    case enableHeardMe
    /// Free users: offer Premium at usage milestones (QSO logged, ADIF
    /// export, transmit) instead of the tip prompt.
    case premiumMoments
    /// Ask for an App Store rating after the first few logged QSOs instead
    /// of waiting for a launch count.
    case rateAfterQSO
    /// RX: cut each slot at its UTC boundary on the audio's own time, so a
    /// sequencer the system wakes late (background) still decodes the slot.
    /// Off: slots are cut when the sequencer asks, as in 1.3.1.
    case rxSlotCutOnAudioTime

    var defaultValue: Bool {
        switch self {
        case .showLogsView:
            #if DEBUG
            return true
            #else
            return false
            #endif
        case .backgroundToast: return false
        case .enableIpadDashboard: return false
        case .newConfigView: return true
        case .donationsEnabled: return true
        // Off everywhere, including debug builds: switch it on from the
        // Debug screen (or Remote Config in release) when wanted.
        case .enableFreeText, .controlsSheet, .enableHeardMe: return false
        // Off everywhere until switched on from the Debug screen or Remote Config.
        case .premiumMoments, .rateAfterQSO: return false
        // Off everywhere until the look is settled.
        case .waterfallSlotContext: return false
        // On in debug builds for device testing. Off in release until the
        // Remote Config rollout turns it on: a missing key keeps 1.3.1's behaviour.
        case .rxSlotCutOnAudioTime:
            #if DEBUG
            return true
            #else
            return false
            #endif
        case .enableBandHopping, .enableICloudSync, .enablePresence:
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }
}
