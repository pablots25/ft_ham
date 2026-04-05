//
//  PremiumFeature.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import Foundation

/// Enumerates all premium-gated features for centralized access control and analytics.
enum PremiumFeature: String, CaseIterable {
    case catControl = "cat_control"
    case pskReporter = "psk_reporter"
    case qrzLogbook = "qrz_logbook_sync"
    case lotwSync = "lotw_sync"
    case eqslSync = "eqsl_sync"
    case iPadDashboard = "ipad_dashboard"

    var displayName: String {
        switch self {
        case .catControl: return "CAT Control"
        case .pskReporter: return "PSK Reporter"
        case .qrzLogbook: return "QRZ Logbook"
        case .lotwSync: return "LoTW"
        case .eqslSync: return "eQSL"
        case .iPadDashboard: return "iPad Dashboard"
        }
    }

    var icon: String {
        switch self {
        case .catControl: return "dot.radiowaves.left.and.right"
        case .pskReporter: return "chart.bar.fill"
        case .qrzLogbook: return "network"
        case .lotwSync: return "checkmark.seal"
        case .eqslSync: return "envelope.badge.shield.half.filled"
        case .iPadDashboard: return "rectangle.split.3x1"
        }
    }

    /// Analytics source string for paywall tracking
    var analyticsSource: String { rawValue }
}
