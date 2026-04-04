//
//  LogSyncManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import Foundation
import Combine

// MARK: - Log Sync Strategy

/// Determines which services a QSO must be confirmed by.
enum LogSyncStrategy: String, CaseIterable {
    case qrzOnly   = "QRZ only"
    case lotwOnly  = "LoTW only"
    case either    = "Any (QRZ or LoTW)"
    case both      = "Both QRZ and LoTW"
}

// MARK: - Log Sync Manager

/// Coordinates QRZ and LoTW uploads when QSOs are logged.
/// Builds ADIF records from LogEntry and delegates to the protocol-based services.
/// Queuing and retry for failed uploads is managed here via a persistent pending set.
@MainActor
final class LogSyncManager: ObservableObject {

    static let shared = LogSyncManager()

    private enum StorageKeys {
        static let pendingQRZIDs = "pendingQRZIDs"
        static let pendingLoTWIDs = "pendingLoTWIDs"
    }

    // MARK: - Services (set via PremiumFeatures factory)
    private(set) var qrzService: (any QRZServiceProtocol) = QRZServiceStub.shared
    private(set) var lotwService: (any LoTWServiceProtocol) = LoTWServiceStub.shared

    // MARK: - Settings (read from AppStorage-backed UserDefaults)
    private var qrzAutoUpload: Bool { UserDefaults.standard.bool(forKey: "qrzAutoUpload") }
    private var lotwAutoUpload: Bool { UserDefaults.standard.bool(forKey: "lotwAutoUpload") }
    private var confirmIntervalHours: Int {
        let v = UserDefaults.standard.integer(forKey: "qrzConfirmationIntervalHours")
        return v > 0 ? v : 6
    }

    // MARK: - Pending upload queue (indexed by LogEntry.id string)
    @Published private(set) var pendingQRZIDs: Set<String> = []
    @Published private(set) var pendingLoTWIDs: Set<String> = []

    // MARK: - Published combined badge count
    @Published private(set) var totalPendingCount: Int = 0

    private let logger = AppLogger(category: "SYNC")
    private var confirmationTimer: Task<Void, Never>?

    private init() {
        loadPendingIDs()
        qrzService = PremiumFeatures.qrzService
        lotwService = PremiumFeatures.lotwService
        updatePendingCount()
        startConfirmationTimer()
    }

    /// Creates an isolated instance for unit testing with injected services.
    /// Does **not** start the confirmation timer or load persisted pending IDs.
    init(qrzService: any QRZServiceProtocol, lotwService: any LoTWServiceProtocol) {
        self.qrzService = qrzService
        self.lotwService = lotwService
    }

    deinit {
        confirmationTimer?.cancel()
    }

    // MARK: - Public: Called after a QSO is logged

    /// Upload a newly logged QSO to enabled services.
    /// Called from `FT8ViewModel+QSOLogger` after appending to qsoList.
    func syncNewQSO(_ entry: LogEntry) {
        let adif = buildSingleEntryADIF(entry)
        let idString = entry.id.uuidString

        if qrzAutoUpload && qrzService.hasAPIKey {
            insertPendingID(idString, into: &pendingQRZIDs, storageKey: StorageKeys.pendingQRZIDs)
            Task {
                let result = await qrzService.uploadADIF(adif)
                if result.success {
                    removePendingID(idString, from: &pendingQRZIDs, storageKey: StorageKeys.pendingQRZIDs)
                    logger.info("QRZ upload success for \(entry.callsign)")
                } else {
                    logger.warning("QRZ upload failed for \(entry.callsign): \(result.errorMessage ?? "unknown")")
                }
            }
        }

        if lotwAutoUpload && lotwService.hasCertificate {
            insertPendingID(idString, into: &pendingLoTWIDs, storageKey: StorageKeys.pendingLoTWIDs)
            Task {
                let result = await lotwService.uploadADIF(adif)
                if result.success {
                    removePendingID(idString, from: &pendingLoTWIDs, storageKey: StorageKeys.pendingLoTWIDs)
                    logger.info("LoTW upload success for \(entry.callsign)")
                } else {
                    logger.warning("LoTW upload failed for \(entry.callsign): \(result.errorMessage ?? "unknown")")
                }
            }
        }
    }

    /// Retry all pending uploads using the current qsoList.
    func retryPendingUploads(_ allEntries: [LogEntry]) {
        pruneOrphanedPendingIDs(validIDs: Set(allEntries.map { $0.id.uuidString }))

        let pendingQRZ = allEntries.filter { pendingQRZIDs.contains($0.id.uuidString) }
        let pendingLoTW = allEntries.filter { pendingLoTWIDs.contains($0.id.uuidString) }

        for entry in pendingQRZ {
            let adif = buildSingleEntryADIF(entry)
            let idString = entry.id.uuidString
            Task {
                let result = await qrzService.uploadADIF(adif)
                if result.success {
                    removePendingID(idString, from: &pendingQRZIDs, storageKey: StorageKeys.pendingQRZIDs)
                }
            }
        }

        for entry in pendingLoTW {
            let adif = buildSingleEntryADIF(entry)
            let idString = entry.id.uuidString
            Task {
                let result = await lotwService.uploadADIF(adif)
                if result.success {
                    removePendingID(idString, from: &pendingLoTWIDs, storageKey: StorageKeys.pendingLoTWIDs)
                }
            }
        }
    }

    /// Trigger a confirmation check on demand.
    func checkConfirmations() {
        let since = Date(timeIntervalSinceNow: -Double(confirmIntervalHours) * 3600)
        Task {
            _ = await qrzService.fetchConfirmations(since: since)
            _ = await lotwService.fetchConfirmations(since: since)
            logger.info("Confirmation check completed")
        }
    }

    // MARK: - Private: ADIF Builder

    func buildSingleEntryADIF(_ entry: LogEntry) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timeFormatter.dateFormat = "HHmmss"

        var adif = ""
        adif += adifField("CALL", entry.callsign)
        adif += adifField("QSO_DATE", dateFormatter.string(from: entry.date))
        adif += adifField("TIME_ON", timeFormatter.string(from: entry.date))
        adif += adifField("MODE", entry.mode)
        adif += adifField("BAND", entry.band)
        adif += adifField("RST_SENT", entry.rstSent)
        adif += adifField("RST_RCVD", entry.rstRcvd)
        if !entry.grid.isEmpty {
            adif += adifField("GRIDSQUARE", entry.grid)
        }
        if let freq = entry.frequencyHz {
            adif += adifField("FREQ", String(format: "%.6f", freq / 1_000_000))
        }
        if let station = entry.stationCallsign, !station.isEmpty {
            adif += adifField("STATION_CALLSIGN", station)
        }
        adif += "<EOR>"
        return adif
    }

    private func adifField(_ name: String, _ value: String) -> String {
        "<\(name):\(value.count)>\(value) "
    }

    private func loadPendingIDs() {
        pendingQRZIDs = loadPendingIDs(forKey: StorageKeys.pendingQRZIDs)
        pendingLoTWIDs = loadPendingIDs(forKey: StorageKeys.pendingLoTWIDs)
    }

    private func loadPendingIDs(forKey key: String) -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }

        return decoded
    }

    private func insertPendingID(_ id: String, into set: inout Set<String>, storageKey: String) {
        set.insert(id)
        persistPendingIDs(set, forKey: storageKey)
    }

    private func removePendingID(_ id: String, from set: inout Set<String>, storageKey: String) {
        set.remove(id)
        persistPendingIDs(set, forKey: storageKey)
    }

    private func persistPendingIDs(_ ids: Set<String>, forKey key: String) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let encoded = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(encoded, forKey: key)
        }

        updatePendingCount()
    }

    private func pruneOrphanedPendingIDs(validIDs: Set<String>) {
        let prunedQRZIDs = pendingQRZIDs.intersection(validIDs)
        if prunedQRZIDs != pendingQRZIDs {
            pendingQRZIDs = prunedQRZIDs
            persistPendingIDs(prunedQRZIDs, forKey: StorageKeys.pendingQRZIDs)
        }

        let prunedLoTWIDs = pendingLoTWIDs.intersection(validIDs)
        if prunedLoTWIDs != pendingLoTWIDs {
            pendingLoTWIDs = prunedLoTWIDs
            persistPendingIDs(prunedLoTWIDs, forKey: StorageKeys.pendingLoTWIDs)
        }
    }

    // MARK: - Private: Confirmation timer

    private func startConfirmationTimer() {
        confirmationTimer?.cancel()
        confirmationTimer = Task {
            while !Task.isCancelled {
                let intervalSeconds = Double(confirmIntervalHours) * 3600
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled else { break }
                checkConfirmations()
            }
        }
    }

    private func updatePendingCount() {
        totalPendingCount = pendingQRZIDs.count + pendingLoTWIDs.count
    }
}
