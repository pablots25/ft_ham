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
/// phrase. The badges are not fixed-size: in a tight row they truncate before
/// the message text does.
struct NeededBadgeView: View {
    let status: NeededStatus

    var body: some View {
        if status.contains(.grid) || status.contains(.dxcc) {
            HStack(spacing: 3) {
                if status.contains(.dxcc) {
                    badge("DXCC", accessibilityLabel: "NEW DXCC", color: .red)
                }
                if status.contains(.grid) {
                    badge("GRID", accessibilityLabel: "NEW GRID", color: .teal)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func badge(_ tag: String, accessibilityLabel: LocalizedStringKey, color: Color) -> some View {
        Text(verbatim: tag)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel(Text(accessibilityLabel))
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
