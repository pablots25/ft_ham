//
//  MessageRowColors.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/09/26.
//

import Combine
import SwiftUI

/// Each kind of decoded row that gets its own background tint. The operator
/// can change the base color of every one in Display settings.
enum MessageRowColor: String, CaseIterable, Identifiable {
    case ownTX
    case cq
    case newCallsign
    case gridToMe
    case reportToMe
    case finals
    case unknown
    case callingMe
    case watched

    var id: Self { self }

    var defaultColor: Color {
        switch self {
        case .ownTX: .yellow
        case .cq: .purple
        case .newCallsign: .green
        case .gridToMe: .blue
        case .reportToMe: .orange
        case .finals: .purple
        case .unknown: .gray
        case .callingMe: .red
        case .watched: .cyan
        }
    }

    /// Shared by the color legend and the color settings.
    var label: LocalizedStringKey {
        switch self {
        case .ownTX: "Your own CQ and free-text transmissions"
        case .cq: "Received CQ from another station"
        case .newCallsign: "Received CQ from a station not yet in your log"
        case .gridToMe: "Message directed to you (grid exchange)"
        case .reportToMe: "Message directed to you (signal report)"
        case .finals: "Final exchange — RR73 / RRR / 73"
        case .unknown: "Unknown message type"
        case .callingMe: "A station calling you"
        case .watched: "A station on your watchlist"
        }
    }
}

/// The row colors in use, persisted in UserDefaults as hex strings. Tints are
/// built once per change: `rowTint` bridges to a dynamic UIColor, which is too
/// costly to repeat for every row on every body pass.
///
/// Not actor-isolated so `backgroundColor(for:)` stays callable from any
/// context. It is only mutated from the settings UI on the main thread.
final class RowColorStore: ObservableObject, @unchecked Sendable {

    static let shared = RowColorStore()

    static let defaultsKey = "messageRowColors"

    @Published private(set) var colors: [MessageRowColor: Color] = [:]
    private(set) var tints: [MessageRowColor: Color] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Base color chosen for a row kind (the default when never changed).
    func color(_ kind: MessageRowColor) -> Color {
        colors[kind] ?? kind.defaultColor
    }

    /// Scheme-adaptive row background for a row kind.
    func tint(_ kind: MessageRowColor) -> Color {
        tints[kind] ?? rowTint(kind.defaultColor)
    }

    var isCustomized: Bool {
        !(defaults.dictionary(forKey: Self.defaultsKey) ?? [:]).isEmpty
    }

    func setColor(_ color: Color, for kind: MessageRowColor) {
        var stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        stored[kind.rawValue] = Self.hex(from: color)
        defaults.set(stored, forKey: Self.defaultsKey)
        load()
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: Self.defaultsKey)
        load()
    }

    private func load() {
        let stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        var colors: [MessageRowColor: Color] = [:]
        var tints: [MessageRowColor: Color] = [:]
        for kind in MessageRowColor.allCases {
            let color = stored[kind.rawValue].flatMap(Self.color(fromHex:)) ?? kind.defaultColor
            colors[kind] = color
            tints[kind] = rowTint(color)
        }
        self.tints = tints
        self.colors = colors
    }

    // MARK: - Hex

    /// "#RRGGBB" in sRGB. Opacity is not stored: tints apply their own.
    static func hex(from color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    static func color(fromHex hex: String) -> Color? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
