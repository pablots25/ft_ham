//
//  CloudLogbookProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import Foundation

// MARK: - Data structures (mirrored in the premium package)

/// One logbook entry as stored in the user's private iCloud database.
/// `dedupKey` is the record name, so the same QSO logged on two devices
/// collapses into one record.
public struct CloudLogRecord: Codable, Hashable, Sendable {
    public let dedupKey: String
    /// `LogEntry.id` on the device that created the record; informational.
    public let sourceID: String
    public let callsign: String
    public let grid: String
    public let date: Date
    public let frequencyHz: Double?
    public let mode: String
    public let band: String
    public let rstSent: String
    public let rstRcvd: String
    public let stationCallsign: String?
    public let cqModifier: String?
    public let mySigInfo: String?
    public let country: String?
    public let flag: String?
    public let qrzStatusRaw: String
    public let lotwStatusRaw: String

    public init(
        dedupKey: String, sourceID: String, callsign: String, grid: String, date: Date,
        frequencyHz: Double?, mode: String, band: String, rstSent: String, rstRcvd: String,
        stationCallsign: String?, cqModifier: String?, mySigInfo: String?, country: String?,
        flag: String?, qrzStatusRaw: String, lotwStatusRaw: String
    ) {
        self.dedupKey = dedupKey
        self.sourceID = sourceID
        self.callsign = callsign
        self.grid = grid
        self.date = date
        self.frequencyHz = frequencyHz
        self.mode = mode
        self.band = band
        self.rstSent = rstSent
        self.rstRcvd = rstRcvd
        self.stationCallsign = stationCallsign
        self.cqModifier = cqModifier
        self.mySigInfo = mySigInfo
        self.country = country
        self.flag = flag
        self.qrzStatusRaw = qrzStatusRaw
        self.lotwStatusRaw = lotwStatusRaw
    }
}

public enum CloudSyncAccountStatus: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case unknown
}

public struct CloudPullResult: Sendable {
    public let upserted: [CloudLogRecord]
    public let deletedKeys: [String]

    public init(upserted: [CloudLogRecord], deletedKeys: [String]) {
        self.upserted = upserted
        self.deletedKeys = deletedKeys
    }
}

public enum CloudLogbookSyncError: Error, Equatable {
    case premiumRequired
    case notAvailable
    case network(String)
    case server(String)
}

// MARK: - Protocol

/// Transport to the user's private CloudKit database. The app-side
/// `CloudLogbookSyncManager` decides what to push and how to merge.
@MainActor
public protocol CloudLogbookSyncProtocol: AnyObject {
    func accountStatus() async -> CloudSyncAccountStatus
    /// Upserts records (record name = dedupKey).
    func push(_ records: [CloudLogRecord]) async throws
    /// Changes since the last call (change token persisted by the service).
    func pullChanges() async throws -> CloudPullResult
    /// Deletes every record in the logbook zone and forgets the change token.
    func deleteAllRemote() async throws
    /// Forgets the change token so the next pull is a full fetch.
    func resetChangeToken()
}
