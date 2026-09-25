//
//  WatchList.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/09/26.
//

import Foundation

/// Callsigns the operator wants to spot (a DXpedition, a friend). Stored as a
/// comma-separated string so it fits in a single `@AppStorage` key.
struct WatchList: Equatable {

    private enum Constants {
        static let separator = ","
        static let minLength = 3
        static let maxLength = 12
    }

    /// Normalized callsigns in the order they were added.
    private(set) var callsigns: [String]
    /// Same callsigns, for per-row lookups.
    private(set) var set: Set<String>

    init(callsigns: [String] = []) {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in callsigns {
            guard let call = Self.normalize(raw), seen.insert(call).inserted else { continue }
            ordered.append(call)
        }
        self.callsigns = ordered
        self.set = seen
    }

    init(storage: String) {
        self.init(callsigns: storage.components(separatedBy: CharacterSet(charactersIn: ", \n\t;")))
    }

    var storage: String { callsigns.joined(separator: Constants.separator) }

    var isEmpty: Bool { callsigns.isEmpty }

    /// Adds a callsign. Returns false when it is not a valid callsign or is
    /// already on the list.
    @discardableResult
    mutating func add(_ raw: String) -> Bool {
        guard let call = Self.normalize(raw), !set.contains(call) else { return false }
        callsigns.append(call)
        set.insert(call)
        return true
    }

    mutating func remove(_ call: String) {
        let key = call.uppercased()
        callsigns.removeAll { $0 == key }
        set.remove(key)
    }

    /// True when `callsign` is on the list, ignoring a prefix or suffix such
    /// as "EA8/" or "/P", so "3Y0J" also matches "3Y0J/P".
    func contains(_ callsign: String?) -> Bool {
        guard !set.isEmpty,
              let call = callsign?.uppercased(), !call.isEmpty else { return false }
        if set.contains(call) { return true }
        guard call.contains("/") else { return false }
        return call.split(separator: "/").contains { set.contains(String($0)) }
    }

    /// Uppercased, trimmed callsign, or nil when it cannot be one.
    static func normalize(_ raw: String) -> String? {
        let call = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (Constants.minLength...Constants.maxLength).contains(call.count),
              call.contains(where: \.isNumber),
              call.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "/" })
        else { return nil }
        return call
    }
}

/// Limits watched-station alerts to one per station per interval. A
/// DXpedition transmits every slot, and an alert every 15 seconds would be
/// noise rather than news.
struct WatchAlertThrottle {

    static let defaultInterval: TimeInterval = 10 * 60

    let interval: TimeInterval
    private var lastAlert: [String: Date] = [:]

    init(interval: TimeInterval = WatchAlertThrottle.defaultInterval) {
        self.interval = interval
    }

    /// True (and records the alert) when `callsign` has not alerted within
    /// the interval.
    mutating func shouldAlert(for callsign: String, at now: Date) -> Bool {
        let key = callsign.uppercased()
        if let last = lastAlert[key], now.timeIntervalSince(last) < interval {
            return false
        }
        lastAlert[key] = now
        return true
    }
}
