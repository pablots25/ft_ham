//
//  PresenceProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import Foundation

/// Another FT Ham operator currently on the air, as published to the shared
/// presence map. Only what is shown here is ever shared: callsign, 4-character
/// grid, band and mode — no coordinates, no identifiers.
public struct PresenceStation: Identifiable, Hashable, Sendable {
    public let callsign: String
    public let grid: String
    public let band: String
    public let mode: String
    public let lastSeen: Date

    public var id: String { callsign }

    public init(callsign: String, grid: String, band: String, mode: String, lastSeen: Date) {
        self.callsign = callsign
        self.grid = grid
        self.band = band
        self.mode = mode
        self.lastSeen = lastSeen
    }
}

public enum PresenceError: Error, Equatable {
    case premiumRequired
    case notAvailable
    case network(String)
}

/// Transport for the opt-in presence map (CloudKit public database).
@MainActor
public protocol PresenceServiceProtocol: AnyObject {
    /// Publishes (or refreshes) our own presence record.
    func upsert(callsign: String, grid4: String, band: String, mode: String) async throws
    /// Operators seen since `date`.
    func fetchOnline(since date: Date) async throws -> [PresenceStation]
    /// Withdraws our record (called when opting out).
    func removeMine() async throws
}
