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
    case bandHopping = "band_hopping"
    case iCloudSync = "icloud_sync"
    case presence = "presence"

    /// Localized feature name, as shown on the paywall and locked rows.
    var displayName: String {
        switch self {
        case .catControl: return String(localized: "CAT Control")
        case .pskReporter: return String(localized: "PSK Reporter")
        case .qrzLogbook: return String(localized: "QRZ Logbook")
        case .lotwSync: return String(localized: "LoTW")
        case .eqslSync: return String(localized: "eQSL")
        case .iPadDashboard: return String(localized: "iPad Dashboard")
        case .statistics: return String(localized: "Statistics")
        case .bandHopping: return String(localized: "Band Hopping")
        case .iCloudSync: return String(localized: "iCloud Sync")
        case .presence: return String(localized: "Operators Online")
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
        case .bandHopping: return "arrow.triangle.2.circlepath"
        case .iCloudSync: return "icloud"
        case .presence: return "person.2.wave.2"
        }
    }

    var paywallDescription: String {
        switch self {
        case .iPadDashboard: return "Multitask with a layout optimized for iPad"
        case .pskReporter: return "See in real-time where your signals are received by others"
        case .catControl: return "Control your radio over the network via CAT/UDP"
        case .qrzLogbook: return "Sync QSOs to your QRZ.com logbook automatically"
        case .lotwSync: return "Upload QSOs and fetch LoTW confirmations"
        case .eqslSync: return "Upload QSOs and fetch eQSL confirmations"
        case .statistics: return "Charts, heatmaps and detailed analytics of your QSO activity"
        case .bandHopping: return "Rotate through your favourite bands automatically while idle"
        case .iCloudSync: return "Keep your logbook in step across your devices, privately"
        case .presence: return "See other FT Ham operators on the air right now"
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
        case .bandHopping: return .mint
        case .iCloudSync: return .blue
        case .presence: return .cyan
        }
    }

    /// Remote feature flag that must also be on for the feature to be reachable.
    /// `nil` means the feature is always available to Premium users.
    var featureFlag: FeatureFlag? {
        switch self {
        case .iPadDashboard: return .enableIpadDashboard
        case .bandHopping: return .enableBandHopping
        case .iCloudSync: return .enableICloudSync
        case .presence: return .enablePresence
        case .pskReporter, .catControl, .qrzLogbook, .lotwSync, .eqslSync, .statistics: return nil
        }
    }

    /// Analytics source string for paywall tracking
    var analyticsSource: String { rawValue }
}
