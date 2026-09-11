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
struct NeededBadgeView: View {
    let status: NeededStatus

    var body: some View {
        if status.contains(.grid) || status.contains(.dxcc) {
            HStack(spacing: 3) {
                if status.contains(.dxcc) {
                    badge("NEW DXCC", color: .red)
                }
                if status.contains(.grid) {
                    badge("NEW GRID", color: .teal)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func badge(_ key: LocalizedStringKey, color: Color) -> some View {
        Text(key)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview {
    VStack(alignment: .leading) {
        NeededBadgeView(status: [.grid])
        NeededBadgeView(status: [.dxcc])
        NeededBadgeView(status: [.grid, .dxcc, .callsign])
        NeededBadgeView(status: [.callsign])
    }
    .padding()
}
