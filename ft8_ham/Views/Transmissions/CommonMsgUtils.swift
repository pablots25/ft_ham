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

// Color selector based on FT8 message type with adaptive colors for dark mode.
// `isNewCallsign` highlights an incoming CQ from a station not yet worked.
func backgroundColor(for msg: FT8Message, isNewCallsign: Bool = false) -> Color {
    switch msg.msgType {
    case .internalTimestamp:
        Color(UIColor.systemBackground)
    case .cq:
        if msg.isTX {
            rowTint(.yellow)
        } else if isNewCallsign {
            rowTint(.green) // new (unworked) callsign
        } else {
            rowTint(.purple)
        }
    case .gridExchange:
        if msg.forMe {
            rowTint(.blue)
        } else {
            Color(UIColor.systemBackground)
        }
    case .standardSignalReport, .rSignalReport:
        if msg.forMe {
            rowTint(.orange)
        } else {
            Color(UIColor.systemBackground)
        }
    case .rr73, .rrr, .final73:
        rowTint(.purple)
    case .unknown:
        rowTint(.gray)
    }
}
