//
//  ViewMode.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case vertical = "Vertical"
    case separated = "TX/RX Separated"
    case condensed = "Condensed"
    case dashboard = "Dashboard"

    var id: String { rawValue }

    var textKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var isIPadOnly: Bool {
        #if DEBUG
        return false
        #else
        return self == .dashboard
        #endif
    }
}
