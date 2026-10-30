//
//  NeededBadgeSettings.swift
//  ft_ham
//

import Foundation

/// The GRID and DXCC badges on decoded rows can be turned on and off
/// separately. They used to share one `showNeededBadges` switch, which now
/// only seeds both new settings so nobody sees badges they had turned off.
enum NeededBadgeSettings {
    static let gridKey = "showNeededGridBadge"
    static let dxccKey = "showNeededDXCCBadge"
    /// The single switch used before 1.3.0.
    static let legacyKey = "showNeededBadges"

    /// Default for both settings: the old shared switch, or on.
    static func legacyDefault(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: legacyKey) as? Bool ?? true
    }

    /// The badges a row shows, given which of them are turned on.
    static func visible(_ status: NeededStatus, showGrid: Bool, showDXCC: Bool) -> NeededStatus {
        var visible = status.intersection([.grid, .dxcc])
        if !showGrid { visible.remove(.grid) }
        if !showDXCC { visible.remove(.dxcc) }
        return visible
    }
}
