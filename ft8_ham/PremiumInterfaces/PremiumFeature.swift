//
//  PremiumFeature.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import SwiftUI

/// Enumerates all premium-gated features for centralized access control and analytics.
enum PremiumFeature: String, CaseIterable {
    case iPadDashboard = "ipad_dashboard"
    case pskReporter = "psk_reporter"
    case catControl = "cat_control"
    case qrzLogbook = "qrz_logbook_sync"
    case lotwSync = "lotw_sync"
    case eqslSync = "eqsl_sync"
    case statistics = "statistics"

    var displayName: String {
        switch self {
        case .catControl: return "CAT Control"
        case .pskReporter: return "PSK Reporter"
        case .qrzLogbook: return "QRZ Logbook"
        case .lotwSync: return "LoTW"
        case .eqslSync: return "eQSL"
        case .iPadDashboard: return "iPad Dashboard"
        case .statistics: return "Statistics"
        }
    }

    var icon: String {
        switch self {
        case .catControl: return "slider.horizontal.3"
        case .pskReporter: return "chart.bar.fill"
        case .qrzLogbook: return "network"
        case .lotwSync: return "checkmark.seal"
        case .eqslSync: return "envelope.badge.shield.half.filled"
        case .iPadDashboard: return "rectangle.split.3x1"
        case .statistics: return "chart.bar.xaxis"
        }
    }

    var paywallDescription: String {
        switch self {
        case .iPadDashboard: return "Multitask with a layout optimised for iPad"
        case .pskReporter: return "See in real-time where your signals are received by others"
        case .catControl: return "Control your radio over the network via CAT/UDP"
        case .qrzLogbook: return "Sync QSOs to your QRZ.com logbook automatically"
        case .lotwSync: return "Upload QSOs and fetch LoTW confirmations"
        case .eqslSync: return "Upload QSOs and fetch eQSL confirmations"
        case .statistics: return "Charts, heatmaps and detailed analytics of your QSO activity"
        }
    }

    var paywallIconColor: Color {
        switch self {
        case .iPadDashboard: return .blue
        case .pskReporter: return .purple
        case .catControl: return .orange
        case .qrzLogbook: return .teal
        case .lotwSync: return .green
        case .eqslSync: return .cyan
        case .statistics: return .indigo
        }
    }

    /// Analytics source string for paywall tracking
    var analyticsSource: String { rawValue }
}
