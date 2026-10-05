//
//  NeededBadgeView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import SwiftUI

/// Small capsules flagging what a decoded station would add to the logbook
/// on the current band/mode. A new *callsign* is already conveyed by the
/// green row tint, so only grid and DXCC are shown here.
///
/// The visible text is the short, untranslated tag ("DXCC", "GRID") so the
/// badges stay narrow in every language. VoiceOver reads the full localized
/// phrase. In a tight row the tags step down to their initials, then to
/// colored dots, instead of being clipped into unreadable fragments. The
/// message text keeps priority over them.
struct NeededBadgeView: View {
    let status: NeededStatus

    var body: some View {
        if status.contains(.grid) || status.contains(.dxcc) {
            ViewThatFits(in: .horizontal) {
                badges(style: .full)
                badges(style: .initial)
                badges(style: .dot)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    enum Style { case full, initial, dot }

    /// Visible text of a badge in each style; `nil` draws a dot.
    static func label(for tag: String, style: Style) -> String? {
        switch style {
        case .full: tag
        case .initial: String(tag.prefix(1))
        case .dot: nil
        }
    }

    private var accessibilityText: Text {
        switch (status.contains(.dxcc), status.contains(.grid)) {
        case (true, true): Text("NEW DXCC") + Text(verbatim: ", ") + Text("NEW GRID")
        case (true, false): Text("NEW DXCC")
        default: Text("NEW GRID")
        }
    }

    private func badges(style: Style) -> some View {
        HStack(spacing: 3) {
            if status.contains(.dxcc) {
                badge("DXCC", color: .red, style: style)
            }
            if status.contains(.grid) {
                badge("GRID", color: .teal, style: style)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func badge(_ tag: String, color: Color, style: Style) -> some View {
        if let label = Self.label(for: tag, style: style) {
            Text(verbatim: label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(color.opacity(0.15), in: Capsule())
        } else {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        NeededBadgeView(status: [.grid])
        NeededBadgeView(status: [.dxcc])
        NeededBadgeView(status: [.grid, .dxcc, .callsign])
        NeededBadgeView(status: [.callsign])
        NeededBadgeView(status: [.grid, .dxcc])
            .frame(width: 40)
    }
    .padding()
}
