//
//  WaterfallDisplaySettings.swift
//  ft_ham
//
//  Created by Pablo Turrion on 21/9/26.
//

import Foundation

/// How the waterfall levels and colors its rows. Edited from the Waterfall
/// settings screen, persisted in UserDefaults, applied by the view model.
struct WaterfallDisplaySettings: Equatable, Sendable {
    var palette: WaterfallPalette = .default
    /// Remove the passband's shape so the noise reads level across the band.
    var flatten: Bool = true
    /// Track the noise floor and keep the color window on it; the built-in
    /// mic and a line-level sound card differ by tens of dB, and no single
    /// fixed window suits both.
    var autoLevel: Bool = true
    /// Auto: how far below the tracked floor the bottom color starts.
    /// Manual: the level, in dB, that maps to the bottom color (relative
    /// to the noise once flattened; absolute in ft8_lib's scale otherwise).
    var zeroDB: Float = 6
    var manualFloorDB: Float = -6
    /// dB from the bottom color to the top one.
    var gainDB: Float = 40

    static let zeroRange: ClosedRange<Float> = 0 ... 20
    static let manualFloorRange: ClosedRange<Float> = -100 ... 20
    static let gainRange: ClosedRange<Float> = 10 ... 80

    // MARK: Persistence

    private enum Key {
        static let palette = "waterfall.palette"
        static let flatten = "waterfall.flatten"
        static let autoLevel = "waterfall.autoLevel"
        static let zeroDB = "waterfall.zeroDB"
        static let manualFloorDB = "waterfall.manualFloorDB"
        static let gainDB = "waterfall.gainDB"
    }

    static func load(from defaults: UserDefaults = .standard) -> WaterfallDisplaySettings {
        var s = WaterfallDisplaySettings()
        if let raw = defaults.string(forKey: Key.palette), let p = WaterfallPalette(rawValue: raw) { s.palette = p }
        if defaults.object(forKey: Key.flatten) != nil { s.flatten = defaults.bool(forKey: Key.flatten) }
        if defaults.object(forKey: Key.autoLevel) != nil { s.autoLevel = defaults.bool(forKey: Key.autoLevel) }
        if defaults.object(forKey: Key.zeroDB) != nil {
            s.zeroDB = defaults.float(forKey: Key.zeroDB).clamped(to: zeroRange)
        }
        if defaults.object(forKey: Key.manualFloorDB) != nil {
            s.manualFloorDB = defaults.float(forKey: Key.manualFloorDB).clamped(to: manualFloorRange)
        }
        if defaults.object(forKey: Key.gainDB) != nil {
            s.gainDB = defaults.float(forKey: Key.gainDB).clamped(to: gainRange)
        }
        return s
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(palette.rawValue, forKey: Key.palette)
        defaults.set(flatten, forKey: Key.flatten)
        defaults.set(autoLevel, forKey: Key.autoLevel)
        defaults.set(zeroDB, forKey: Key.zeroDB)
        defaults.set(manualFloorDB, forKey: Key.manualFloorDB)
        defaults.set(gainDB, forKey: Key.gainDB)
    }
}
