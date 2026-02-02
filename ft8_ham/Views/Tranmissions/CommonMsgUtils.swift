//
//  CommonMsgUtils.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 4/1/26.
//

import SwiftUI

// Color selector based on FT8 message type with adaptive colors for dark mode
func backgroundColor(for msg: FT8Message) -> Color {
    switch msg.msgType {
    case .internalTimestamp:
        Color(UIColor.systemBackground)
    case .cq:
        if msg.isTX {
            Color.yellow.opacity(0.2) // soft yellow
        } else {
            Color.purple.opacity(0.2) // soft purple
        }
    case .gridExchange:
        if msg.forMe {
            Color.blue.opacity(0.2) // soft blue
        } else {
            Color(UIColor.systemBackground)
        }
    case .standardSignalReport, .rSignalReport:
        if msg.forMe {
            Color.orange.opacity(0.2) // soft orange
        } else {
            Color(UIColor.systemBackground)
        }
    case .rr73, .rrr, .final73:
        Color.purple.opacity(0.2) // soft purple
    case .unknown:
        Color.gray.opacity(0.2) // soft gray
    }
}
