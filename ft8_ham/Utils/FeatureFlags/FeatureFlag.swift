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
        case .newConfigView: return false
        case .donationsEnabled: return true
        // Off everywhere, including debug builds: switch it on from the
        // Debug screen (or Remote Config in release) when wanted.
        case .enableFreeText, .controlsSheet, .enableHeardMe: return false
        // Off everywhere until the look is settled.
        case .waterfallSlotContext: return false
        case .enableBandHopping, .enableICloudSync, .enablePresence:
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }
}
