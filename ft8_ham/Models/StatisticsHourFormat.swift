//
//  StatisticsHourFormat.swift
//  ft_ham
//

import SwiftUI

/// Clock used for the hour labels in Statistics (24-hour or 12-hour AM/PM).
/// Statistics lives in the premium package, which reads the same key with
/// its own `StatsHourFormat`. The raw values must stay in step with it.
enum StatisticsHourFormat: String, CaseIterable, Identifiable {
    case twentyFourHour = "24h"
    case twelveHour = "12h"

    static let storageKey = "statisticsHourFormat"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .twentyFourHour: "24-hour"
        case .twelveHour: "12-hour (AM/PM)"
        }
    }
}
