//
//  CloudLogbookSyncManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import Foundation
import Combine

/// Keeps the local ADIF logbook and the user's private iCloud copy in step.
///
/// Mirrors `LogSyncManager`: new and imported QSOs are queued and pushed,
/// and a pull on launch/foreground merges whatever other devices logged.
/// The merge reuses the logbook's own duplicate rule, so a QSO that crossed
/// a minute boundary on another device does not appear twice.
@MainActor
final class CloudLogbookSyncManager: ObservableObject {
    static let shared = CloudLogbookSyncManager()

    static let enabledKey = "iCloudLogbookSyncEnabled"
    static let pendingKey = "pendingCloudKeys"

    @Published private(set) var accountStatus: CloudSyncAccountStatus = .unknown
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncDate: Date?
    /// Dedup keys waiting to be pushed (kept across launches).
    @Published private(set) var pendingKeys: Set<String> = []

    /// User toggle; independent from the feature flag and the entitlement.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.enabledKey)
            guard newValue else { return }
            Task { await refreshAccountStatus() }
        }
    }

    /// True when the feature may actually talk to CloudKit.
    var isActive: Bool { isEnabled && gate() }

    weak var viewModel: FT8ViewModel?

    private let injectedService: (any CloudLogbookSyncProtocol)?
    private lazy var service: any CloudLogbookSyncProtocol = injectedService ?? PremiumFeatures.cloudLogbookSync
    private let defaults: UserDefaults
    private let gate: () -> Bool
    private let logger = AppLogger(category: "ICLOUD")

    /// `service` is resolved inside the initialiser rather than as a default
    /// argument: default-argument expressions are evaluated in the caller's
    /// (nonisolated) context, which cannot touch the MainActor-isolated factory.
    init(
        service: (any CloudLogbookSyncProtocol)? = nil,
        defaults: UserDefaults = .standard,
        gate: @escaping () -> Bool = CloudLogbookSyncManager.defaultGate
    ) {
        self.injectedService = service
        self.defaults = defaults
        self.gate = gate
        pendingKeys = Set(defaults.stringArray(forKey: Self.pendingKey) ?? [])
    }

    static func defaultGate() -> Bool {
        FeatureFlagManager.shared.isEnabled(.enableICloudSync) && PremiumManager.shared.isPremiumUnlocked
    }

    // MARK: - Account

    func refreshAccountStatus() async {
        guard gate() else { return }
        accountStatus = await service.accountStatus()
    }

    // MARK: - Push

    /// Queues a freshly logged QSO and tries to push it right away.
    func syncNewQSO(_ entry: LogEntry) {
        enqueue([entry])
    }

    /// Queues everything an ADIF import just added.
    func syncImported(_ entries: [LogEntry]) {
        enqueue(entries)
    }

    private func enqueue(_ entries: [LogEntry]) {
        guard isActive, !entries.isEmpty else { return }
        pendingKeys.formUnion(entries.map(\.dedupKey))
        savePending()
        Task { await pushPending() }
    }

    /// Pushes every queued entry that still exists locally.
    func pushPending() async {
        guard isActive, !pendingKeys.isEmpty, !isSyncing else { return }
        let entries = (viewModel?.qsoList ?? []).filter { pendingKeys.contains($0.dedupKey) }
        guard !entries.isEmpty else {
            pendingKeys.removeAll()
            savePending()
            return
        }
        await push(entries, clearingKeys: Set(entries.map(\.dedupKey)))
    }

    /// Uploads the whole logbook (used when enabling sync on a new device).
    func pushAll() async {
        guard isActive, let entries = viewModel?.qsoList, !entries.isEmpty else { return }
        await push(entries, clearingKeys: Set(entries.map(\.dedupKey)))
    }

    private func push(_ entries: [LogEntry], clearingKeys keys: Set<String>) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await service.push(entries.map(\.cloudRecord))
            pendingKeys.subtract(keys)
            savePending()
            lastError = nil
            lastSyncDate = Date()
            logger.info("Pushed \(entries.count) QSO(s) to iCloud")
        } catch {
            // Keep the keys queued; the next hook retries.
            lastError = String(describing: error)
            logger.warning("iCloud push failed: \(String(describing: error))")
        }
    }

    // MARK: - Pull

    /// Fetches changes from other devices and merges them into the logbook.
    func pull() async {
        guard isActive, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await service.pullChanges()
            lastError = nil
            lastSyncDate = Date()
            guard !result.upserted.isEmpty, let viewModel else { return }

            let merged = Self.merge(result.upserted, into: viewModel.qsoList)
            let added = merged.count - viewModel.qsoList.count
            if added > 0 {
                viewModel.qsoList = merged
                logger.info("Merged \(added) QSO(s) from iCloud")
            }
        } catch {
            lastError = String(describing: error)
            logger.warning("iCloud pull failed: \(String(describing: error))")
        }
    }

    // MARK: - Delete

    func deleteAllRemote() async {
        guard isActive else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await service.deleteAllRemote()
            pendingKeys.removeAll()
            savePending()
            lastError = nil
            logger.info("Deleted the iCloud copy of the logbook")
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Forces the next pull to fetch everything (after a local wipe/restore).
    func resetChangeToken() {
        service.resetChangeToken()
    }

    // MARK: - Merge (pure)

    /// Appends cloud records the local logbook does not have yet, keeping the
    /// list sorted by date. A record is "already here" when its dedup key
    /// matches, or when the logbook's own ±120 s duplicate rule matches.
    nonisolated static func merge(_ records: [CloudLogRecord], into existing: [LogEntry]) -> [LogEntry] {
        guard !records.isEmpty else { return existing }
        var result = existing
        var keys = Set(existing.map(\.dedupKey))

        for record in records.sorted(by: { $0.date < $1.date }) {
            guard !keys.contains(record.dedupKey) else { continue }
            let entry = LogEntry(cloud: record)
            let isNearDuplicate = result.contains {
                $0.callsign.caseInsensitiveCompare(entry.callsign) == .orderedSame &&
                $0.band == entry.band &&
                abs($0.date.timeIntervalSince(entry.date)) < 120
            }
            guard !isNearDuplicate else { continue }
            keys.insert(record.dedupKey)
            result.append(entry)
        }

        guard result.count != existing.count else { return existing }
        result.sort { $0.date < $1.date }
        return result
    }

    private func savePending() {
        defaults.set(Array(pendingKeys), forKey: Self.pendingKey)
    }
}
