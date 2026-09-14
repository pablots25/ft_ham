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
    case controlsSheet
    case newConfigView
    case donationsEnabled
    /// Premium: autonomous band hopping over CAT.
    case enableBandHopping
    /// Premium: iCloud logbook sync.
    case enableICloudSync
    /// Premium: "users online" presence on the map.
    case enablePresence

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
        case .controlsSheet: return true
        case .newConfigView: return false
        case .donationsEnabled: return true
        case .enableBandHopping, .enableICloudSync, .enablePresence:
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }
}
