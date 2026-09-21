//
//  WaterfallPalette.swift
//  ft_ham
//
//  Created by Pablo Turrion on 21/9/26.
//

import SwiftUI

/// Colour scales for the waterfall. Each maps a level in 0…1 (bottom of the
/// colour window to its top) to a colour; `lookupTable` bakes it into 256
/// BGRA entries for the row painter.
enum WaterfallPalette: String, CaseIterable, Identifiable, Sendable {
    /// Dark blue floor, cyan and white signals: the classic digital-mode look.
    case blue
    /// The scale the app shipped with: blue → green → yellow → red.
    case classic
    /// Black through red and orange to yellow.
    case fire
    /// Perceptually uniform purple → teal → yellow.
    case viridis
    /// Plain black to white.
    case grey

    var id: String { rawValue }

    static let `default`: WaterfallPalette = .blue

    var title: String {
        switch self {
        case .blue: return String(localized: "Blue")
        case .classic: return String(localized: "Classic")
        case .fire: return String(localized: "Fire")
        case .viridis: return String(localized: "Viridis")
        case .grey: return String(localized: "Grey")
        }
    }

    /// Colour stops as (position 0…1, r, g, b) with channels in 0…255.
    private var stops: [(Double, Double, Double, Double)] {
        switch self {
        case .blue:
            return [(0.00, 0, 0, 0), (0.25, 0, 0, 140), (0.50, 0, 90, 255),
                    (0.75, 0, 230, 255), (1.00, 255, 255, 255)]
        case .classic:
            return [(0.00, 0, 0, 255), (0.25, 0, 255, 255), (0.50, 255, 255, 0),
                    (0.75, 255, 128, 0), (1.00, 255, 0, 0)]
        case .fire:
            return [(0.00, 0, 0, 0), (0.30, 120, 0, 0), (0.60, 255, 60, 0),
                    (0.85, 255, 200, 0), (1.00, 255, 255, 255)]
        case .viridis:
            return [(0.00, 68, 1, 84), (0.25, 59, 82, 139), (0.50, 33, 145, 140),
                    (0.75, 94, 201, 98), (1.00, 253, 231, 37)]
        case .grey:
            return [(0.00, 0, 0, 0), (1.00, 255, 255, 255)]
        }
    }

    /// The colour at `level` (clamped to 0…1) as 0…255 channels.
    func rgb(at level: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(max(level, 0), 1)
        let s = stops
        var upper = 1
        while upper < s.count - 1 && s[upper].0 < t { upper += 1 }
        let lo = s[upper - 1], hi = s[upper]
        let span = hi.0 - lo.0
        let f = span > 0 ? (t - lo.0) / span : 0
        return (lo.1 + (hi.1 - lo.1) * f, lo.2 + (hi.2 - lo.2) * f, lo.3 + (hi.3 - lo.3) * f)
    }

    /// 256 BGRA pixels (little-endian 0xAARRGGBB) for the row painter.
    var lookupTable: [UInt32] {
        (0 ... 255).map { i in
            let c = rgb(at: Double(i) / 255)
            let r = UInt32(c.r.rounded()), g = UInt32(c.g.rounded()), b = UInt32(c.b.rounded())
            return (255 << 24) | (r << 16) | (g << 8) | b
        }
    }

    /// A SwiftUI gradient of the scale, for pickers and previews.
    var gradient: LinearGradient {
        let colors = stride(from: 0.0, through: 1.0, by: 0.05).map { level -> Color in
            let c = rgb(at: level)
            return Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
