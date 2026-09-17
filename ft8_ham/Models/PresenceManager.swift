//
//  PresenceManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import Foundation
import Combine

/// Opt-in "who else is on the air" layer for the map.
///
/// While the sequencer is decoding and the operator has opted in, a tiny
/// record (callsign, 4-character grid, band, mode) is refreshed every few
/// minutes; it is only fetched back while the map is on screen. Records
/// older than `staleAfter` are ignored, so closing the app makes the station
/// disappear on its own.
@MainActor
final class PresenceManager: ObservableObject {
    static let shared = PresenceManager()

    static let optInKey = "presenceOptIn"

    @Published private(set) var stations: [PresenceStation] = []
    @Published private(set) var lastError: String?

    /// Off by default: nothing is published until the operator says so.
    var optIn: Bool {
        get { defaults.bool(forKey: Self.optInKey) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.optInKey)
            if newValue {
                restartPublishing()
            } else {
                Task { await optOut() }
            }
        }
    }

    var isActive: Bool { optIn && gate() }

    private let service: any PresenceServiceProtocol
    private let defaults: UserDefaults
    private let gate: () -> Bool
    private let upsertInterval: TimeInterval
    private let fetchInterval: TimeInterval
    private let staleAfter: TimeInterval
    private let logger = AppLogger(category: "PRESENCE")

    private var publishTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var contextTask: Task<Void, Never>?
    private var context: (callsign: String, grid: String, band: String, mode: String)?
    private var mapVisible = false

    /// `service` is resolved inside the initialiser: a default argument would
    /// be evaluated in the caller's nonisolated context.
    init(
        service: (any PresenceServiceProtocol)? = nil,
        defaults: UserDefaults = .standard,
        gate: @escaping () -> Bool = PresenceManager.defaultGate,
        upsertInterval: TimeInterval = 180,
        fetchInterval: TimeInterval = 180,
        staleAfter: TimeInterval = 900
    ) {
        self.service = service ?? PremiumFeatures.presence
        self.defaults = defaults
        self.gate = gate
        self.upsertInterval = upsertInterval
        self.fetchInterval = fetchInterval
        self.staleAfter = staleAfter
    }

    static func defaultGate() -> Bool {
        FeatureFlagManager.shared.isEnabled(.enablePresence) && PremiumManager.shared.isPremiumUnlocked
    }

    /// Stations to draw: fresh, and never our own callsign.
    var visibleStations: [PresenceStation] {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let me = context?.callsign.uppercased()
        return stations.filter { $0.lastSeen >= cutoff && $0.callsign.uppercased() != me }
    }

    // MARK: - Sequencer lifecycle

    /// The station went on the air: start publishing.
    func sequencerDidStart(callsign: String, grid: String, band: String, mode: String) {
        context = (callsign, grid, band, mode)
        guard isActive, isContextUsable else { return }
        restartPublishing()
    }

    /// The station stopped: stop publishing. The record expires by itself.
    func sequencerDidStop() {
        publishTask?.cancel()
        publishTask = nil
    }

    /// Band, mode or grid changed while on the air; re-publish, debounced so a
    /// band-hop burst does not turn into a burst of writes.
    func contextDidChange(band: String, mode: String, grid: String) {
        guard var current = context else { return }
        current.band = band
        current.mode = mode
        current.grid = grid
        context = current
        guard isActive, publishTask != nil else { return }

        contextTask?.cancel()
        contextTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.publishOnce()
        }
    }

    // MARK: - Map lifecycle

    func mapDidAppear() {
        mapVisible = true
        guard isActive else { return }
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.mapVisible {
                await self.fetchOnce()
                try? await Task.sleep(for: .seconds(self.fetchInterval))
            }
        }
    }

    func mapDidDisappear() {
        mapVisible = false
        fetchTask?.cancel()
        fetchTask = nil
    }

    // MARK: - Opt out

    func optOut() async {
        publishTask?.cancel(); publishTask = nil
        fetchTask?.cancel(); fetchTask = nil
        contextTask?.cancel(); contextTask = nil
        stations = []
        do {
            try await service.removeMine()
        } catch {
            logger.warning("Could not withdraw presence: \(String(describing: error))")
        }
    }

    // MARK: - Internals

    private var isContextUsable: Bool {
        guard let context else { return false }
        return !context.callsign.isEmpty && context.grid.count >= 4
    }

    private func restartPublishing() {
        guard isActive, isContextUsable else { return }
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.publishOnce()
                try? await Task.sleep(for: .seconds(self.upsertInterval))
            }
        }
    }

    private func publishOnce() async {
        guard isActive, let context, isContextUsable else { return }
        do {
            try await service.upsert(
                callsign: context.callsign,
                grid4: String(context.grid.prefix(4)),
                band: context.band,
                mode: context.mode
            )
            lastError = nil
        } catch {
            lastError = String(describing: error)
            logger.warning("Presence publish failed: \(String(describing: error))")
        }
    }

    private func fetchOnce() async {
        guard isActive else { return }
        do {
            stations = try await service.fetchOnline(since: Date().addingTimeInterval(-staleAfter))
            lastError = nil
        } catch {
            lastError = String(describing: error)
            logger.warning("Presence fetch failed: \(String(describing: error))")
        }
    }
}
