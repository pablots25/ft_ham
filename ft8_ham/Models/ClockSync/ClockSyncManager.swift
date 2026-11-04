//
//  ClockSyncManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import Combine

/// Periodically measures the device clock against an SNTP server and feeds
/// the offset into `AppClock`, so slot timing and decode timestamps stay on
/// true UTC even when the phone's clock is a few seconds off.
@MainActor
final class ClockSyncManager: ObservableObject {
    static let shared = ClockSyncManager()

    static let enabledKey = "ntpSyncEnabled"
    /// Above this the operator should fix Settings > Date & Time.
    static let warningThreshold: TimeInterval = 1.0
    /// Offset changes smaller than this are noise and are not applied.
    static let applyThreshold: TimeInterval = 0.02
    /// Samples slower than this are discarded.
    static let maxRoundTrip: TimeInterval = 1.0

    @Published private(set) var offset: TimeInterval = 0
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false

    var isWarning: Bool { abs(offset) > Self.warningThreshold }

    /// User toggle. Disabling drops the correction to zero immediately.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.enabledKey)
            if newValue {
                Task { await syncNow() }
            } else {
                apply(0)
            }
        }
    }

    private let client: any SNTPQuerying
    private let hosts: [String]
    private let defaults: UserDefaults
    private let samplesPerSync: Int
    private let interval: Duration
    private var loopTask: Task<Void, Never>?

    init(
        client: any SNTPQuerying = SNTPClient(),
        hosts: [String] = ["time.apple.com", "pool.ntp.org"],
        defaults: UserDefaults = .standard,
        samplesPerSync: Int = 3,
        interval: Duration = .seconds(30 * 60)
    ) {
        self.client = client
        self.hosts = hosts
        self.defaults = defaults
        self.samplesPerSync = samplesPerSync
        self.interval = interval
    }

    // MARK: - Lifecycle

    /// Syncs now and then every `interval` while the app is alive.
    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                guard let self else { return }
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Sync

    /// Takes a few samples from the first host that answers, drops slow
    /// ones and applies the median offset.
    func syncNow() async {
        guard isEnabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var samples: [SNTPClient.Sample] = []
        var firstError: String?
        for host in hosts {
            for _ in 0..<samplesPerSync {
                do {
                    let sample = try await client.query(host: host)
                    if sample.roundTrip <= Self.maxRoundTrip { samples.append(sample) }
                } catch {
                    firstError = firstError ?? "\(host): \(error)"
                }
            }
            if !samples.isEmpty { break }
        }

        guard !samples.isEmpty else {
            lastError = firstError ?? "no usable samples"
            AppLogger.shared.log(.warning, "[ClockSync] failed: \(lastError ?? "-"); keeping offset \(String(format: "%.3f", offset))s")
            return
        }

        let sorted = samples.map(\.offset).sorted()
        let median = sorted[sorted.count / 2]
        lastError = nil
        lastSyncDate = Date()
        apply(median)
    }

    /// Writes the offset into `AppClock` and publishes it. Small jitter is
    /// ignored so the sequencer does not re-anchor for nothing.
    func apply(_ newOffset: TimeInterval) {
        let previous = offset
        guard abs(newOffset - previous) >= Self.applyThreshold || (newOffset == 0 && previous != 0) else {
            return
        }
        AppClock.shared.offset = newOffset
        offset = newOffset
        AppLogger.shared.info("[ClockSync] offset \(String(format: "%+.3f", newOffset))s (was \(String(format: "%+.3f", previous))s)")
    }
}
