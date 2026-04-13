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
    case statisticsView
    
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
        case .statisticsView:
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }
}
