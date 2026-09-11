//
//  CommonMsgUtils.swift
//  ft_ham
//
//  Created by Pablo Turrion on 4/1/26.
//

import SwiftUI

/// Soft row tint that adapts its opacity per color scheme. The flat 0.2 tints
/// read as too faint over the dark-mode background, so dark mode uses a stronger
/// alpha for adequate contrast.
func rowTint(_ color: Color) -> Color {
    Color(UIColor { trait in
        let alpha: CGFloat = trait.userInterfaceStyle == .dark ? 0.32 : 0.20
        return UIColor(color).withAlphaComponent(alpha)
    })
}

/// The row tints, created once. `rowTint` builds a dynamic UIColor provider and
/// bridges `UIColor(Color)` on every call; doing that per row per body pass was
/// one of the main per-row costs of the message lists.
private enum RowTints {
    static let yellow = rowTint(.yellow)
    static let green = rowTint(.green)
    static let purple = rowTint(.purple)
    static let blue = rowTint(.blue)
    static let orange = rowTint(.orange)
    static let gray = rowTint(.gray)
    static let systemBackground = Color(UIColor.systemBackground)
}

// Color selector based on FT8 message type with adaptive colors for dark mode.
// `isNewCallsign` highlights an incoming CQ from a station not yet worked.
func backgroundColor(for msg: FT8Message, isNewCallsign: Bool = false) -> Color {
    switch msg.msgType {
    case .internalTimestamp:
        RowTints.systemBackground
    case .cq:
        if msg.isTX {
            RowTints.yellow
        } else if isNewCallsign {
            RowTints.green // new (unworked) callsign
        } else {
            RowTints.purple
        }
    case .gridExchange:
        if msg.forMe {
            RowTints.blue
        } else {
            RowTints.systemBackground
        }
    case .standardSignalReport, .rSignalReport:
        if msg.forMe {
            RowTints.orange
        } else {
            RowTints.systemBackground
        }
    case .rr73, .rrr, .final73:
        RowTints.purple
    case .unknown:
        msg.isTX ? RowTints.yellow : RowTints.gray // own free text is yellow
    }
}
