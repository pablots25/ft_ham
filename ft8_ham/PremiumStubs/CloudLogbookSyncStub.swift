//
//  CloudLogbookSyncStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import Foundation

/// No-op iCloud logbook transport used when the premium package is not linked.
@MainActor
public final class CloudLogbookSyncStub: CloudLogbookSyncProtocol {
    public static let shared = CloudLogbookSyncStub()

    private init() {}

    public func accountStatus() async -> CloudSyncAccountStatus { .unknown }

    public func push(_ records: [CloudLogRecord]) async throws {
        throw CloudLogbookSyncError.premiumRequired
    }

    public func pullChanges() async throws -> CloudPullResult {
        throw CloudLogbookSyncError.premiumRequired
    }

    public func deleteAllRemote() async throws {
        throw CloudLogbookSyncError.premiumRequired
    }

    public func resetChangeToken() {}
}
