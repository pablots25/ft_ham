//
//  PresenceServiceStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import Foundation

/// No-op presence transport used when the premium package is not linked.
@MainActor
public final class PresenceServiceStub: PresenceServiceProtocol {
    public static let shared = PresenceServiceStub()

    private init() {}

    public func upsert(callsign: String, grid4: String, band: String, mode: String) async throws {
        throw PresenceError.premiumRequired
    }

    public func fetchOnline(since date: Date) async throws -> [PresenceStation] {
        throw PresenceError.premiumRequired
    }

    public func removeMine() async throws {}
}
