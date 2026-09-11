//
//  HeardMeStore.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import Combine
import CoreLocation

/// Holds the stations that heard us (from PSK Reporter) and enforces the
/// polling etiquette the service asks for: at most one query every five
/// minutes, doubling the wait while it answers with 429/503.
@MainActor
final class HeardMeStore: ObservableObject {
    static let shared = HeardMeStore()

    static let lastFetchKey = "heardMeLastFetch"
    static let windowKey = "heardMeWindow"
    static let maxInterval: TimeInterval = 30 * 60
    /// Keep the list usable on a 24 h query that returns thousands of rows.
    static let maxStations = 500

    @Published private(set) var stations: [HeardMeStation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastFetch: Date?
    @Published private(set) var lastError: String?
    /// Earliest time another query is allowed.
    @Published private(set) var nextAllowedFetch: Date?

    var window: HeardMeWindow {
        get { HeardMeWindow(rawValue: defaults.integer(forKey: Self.windowKey)) ?? .fifteenMinutes }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Self.windowKey)
            // A narrower window is a client-side filter over what we already have.
            stations = Self.filter(allStations, window: newValue, now: Date())
        }
    }

    private let fetcher: any ReceptionReportFetching
    private let defaults: UserDefaults
    private let baseInterval: TimeInterval
    private var currentInterval: TimeInterval
    /// Everything from the last successful fetch, before the window filter.
    private var allStations: [HeardMeStation] = []
    private var fetchedWindow: HeardMeWindow?

    init(
        fetcher: any ReceptionReportFetching = PSKReporterRetrieveClient(),
        defaults: UserDefaults = .standard,
        minInterval: TimeInterval = 5 * 60
    ) {
        self.fetcher = fetcher
        self.defaults = defaults
        self.baseInterval = minInterval
        self.currentInterval = minInterval
        // Survive relaunches so a restart cannot bypass the rate limit.
        if let last = defaults.object(forKey: Self.lastFetchKey) as? Date {
            lastFetch = last
            nextAllowedFetch = last.addingTimeInterval(minInterval)
        }
    }

    var canFetch: Bool {
        guard let next = nextAllowedFetch else { return true }
        return Date() >= next
    }

    /// Seconds until the next query is allowed (0 when allowed now).
    var secondsUntilNextFetch: TimeInterval {
        guard let next = nextAllowedFetch else { return 0 }
        return max(0, next.timeIntervalSince(Date()))
    }

    /// Fetches only if the rate limit allows it; silent otherwise.
    func refreshIfAllowed(callsign: String, myLocator: String) {
        guard canFetch, !isLoading else { return }
        Task { await refresh(callsign: callsign, myLocator: myLocator) }
    }

    /// Fetches now. Still refuses inside the rate-limit window and reports
    /// how long to wait in `lastError`.
    func refresh(callsign: String, myLocator: String) async {
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty else {
            lastError = String(localized: "Set your callsign to see who hears you")
            return
        }
        guard canFetch else {
            lastError = String(format: String(localized: "Next refresh in %@"), Self.format(secondsUntilNextFetch))
            return
        }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        // The window we ask for must cover the one shown; 24 h covers both.
        let requested = window
        let now = Date()
        lastFetch = now
        defaults.set(now, forKey: Self.lastFetchKey)

        do {
            let reports = try await fetcher.fetch(senderCallsign: call, window: requested)
            currentInterval = baseInterval
            allStations = Self.group(reports, myLocator: myLocator, now: now)
            fetchedWindow = requested
            stations = Self.filter(allStations, window: window, now: now)
            lastError = nil
        } catch PSKReporterRetrieveError.rateLimited {
            currentInterval = min(currentInterval * 2, Self.maxInterval)
            lastError = String(localized: "PSK Reporter is busy; trying again later")
        } catch {
            lastError = String(describing: error)
        }
        nextAllowedFetch = now.addingTimeInterval(currentInterval)
    }

    // MARK: - Pure helpers

    /// Groups reports by receiver: best SNR, latest time, distance from us.
    static func group(_ reports: [ReceptionReport], myLocator: String, now: Date = Date()) -> [HeardMeStation] {
        let myCoordinate = MaidenheadGrid.center(for: myLocator)
        var byReceiver: [String: [ReceptionReport]] = [:]
        for report in reports {
            byReceiver[report.receiverCallsign, default: []].append(report)
        }

        var stations: [HeardMeStation] = []
        stations.reserveCapacity(byReceiver.count)
        for (callsign, rows) in byReceiver {
            // Use the most recent report's locator (portable receivers move).
            guard let latest = rows.max(by: { $0.flowStart < $1.flowStart }),
                  let center = MaidenheadGrid.center(for: latest.receiverLocator) else { continue }
            let distance = myCoordinate.map { distanceBetween($0, center) / 1000 }
            stations.append(HeardMeStation(
                callsign: callsign,
                locator: latest.receiverLocator,
                latitude: center.latitude,
                longitude: center.longitude,
                bestSNR: rows.compactMap(\.snr).max(),
                lastHeard: latest.flowStart,
                distanceKm: distance,
                reportCount: rows.count
            ))
        }

        stations.sort { a, b in
            switch (a.distanceKm, b.distanceKm) {
            case let (da?, db?) where da != db: return da < db
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.callsign < b.callsign
            }
        }
        return Array(stations.prefix(maxStations))
    }

    static func filter(_ stations: [HeardMeStation], window: HeardMeWindow, now: Date) -> [HeardMeStation] {
        let cutoff = now.addingTimeInterval(-window.seconds)
        return stations.filter { $0.lastHeard >= cutoff }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
