//
//  FeatureFlag.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 2/2/26.
//

import Foundation

enum FeatureFlag: String, CaseIterable {
    case showLogsView
    case newConfigView
    case backgroundToast
    
    var defaultValue: Bool {
        switch self {
        case .showLogsView: return false
        case .newConfigView: return true
        case .backgroundToast: return false
        }
    }
}
