//
//  ReceptionReport.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import CoreLocation
import SwiftUI

/// One `<receptionReport>` row from PSK Reporter: `receiverCallsign` heard
/// `senderCallsign` at `frequencyHz` with `snr`.
struct ReceptionReport: Identifiable, Hashable, Sendable {
    let receiverCallsign: String
    let receiverLocator: String
    let senderCallsign: String
    let frequencyHz: Int64
    let snr: Int?
    let mode: String
    let flowStart: Date

    var id: String { "\(receiverCallsign)|\(frequencyHz)|\(Int(flowStart.timeIntervalSince1970))" }
}

/// How far back to ask PSK Reporter.
enum HeardMeWindow: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 900
    case twentyFourHours = 86_400

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: LocalizedStringKey {
        switch self {
        case .fifteenMinutes: return "Last 15 min"
        case .twentyFourHours: return "Last 24 h"
        }
    }
}

/// A receiver that heard us, aggregated over its reports.
struct HeardMeStation: Identifiable, Hashable, Sendable {
    let callsign: String
    let locator: String
    let latitude: Double
    let longitude: Double
    let bestSNR: Int?
    let lastHeard: Date
    /// Great-circle distance from our grid, in km; nil when our grid is unknown.
    let distanceKm: Double?
    let reportCount: Int

    var id: String { callsign }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
