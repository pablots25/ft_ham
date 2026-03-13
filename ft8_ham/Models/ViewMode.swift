//
//  ViewMode.swift
//  ft_ham
//

import SwiftUI

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case vertical = "Vertical"
    case separated = "TX/RX Separated"
    case condensed = "Condensed"

    var id: String { rawValue }
    var textKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
