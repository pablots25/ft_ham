//
//  StatisticsEngine.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import Foundation

// MARK: - StatsPeriod

enum StatsPeriod: Hashable, Identifiable {
    case allTime
    case thisYear
    case thisMonth
    case last30Days
    case last7Days
    case custom(Date, Date)

    var id: String {
        switch self {
        case .allTime:            return "allTime"
        case .thisYear:           return "thisYear"
        case .thisMonth:          return "thisMonth"
        case .last30Days:         return "last30Days"
        case .last7Days:          return "last7Days"
        case .custom(let s, _):   return "custom-\(s.timeIntervalSince1970)"
        }
    }

    var label: String {
        switch self {
        case .allTime:      return String(localized: "All Time")
        case .thisYear:     return String(localized: "This Year")
        case .thisMonth:    return String(localized: "This Month")
        case .last30Days:   return String(localized: "Last 30 Days")
        case .last7Days:    return String(localized: "Last 7 Days")
        case .custom:       return String(localized: "Custom")
        }
    }

    /// Returns the start date for the period (nil = no lower bound).
    func startDate(calendar: Calendar = .current) -> Date? {
        let now = Date()
        switch self {
        case .allTime:
            return nil
        case .thisYear:
            return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now)
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .custom(let start, _):
            return start
        }
    }

    /// Returns the end date for the period (nil = no upper bound).
    func endDate(calendar: Calendar = .current) -> Date? {
        switch self {
        case .custom(_, let end):
            return Calendar.current.date(byAdding: .day, value: 1, to: end)
        default:
            return nil
        }
    }
}

// MARK: - StatisticsSummary

struct StatisticsSummary {
    // Totals
    let totalQSOs: Int
    let uniqueCallsigns: Int
    let uniqueCountries: Int
    let uniqueGrids: Int
    let uniqueBands: Int
    let firstQSO: Date?
    let latestQSO: Date?

    // Breakdowns
    let qsosByBand: [(key: String, count: Int)]
    let qsosByMode: [(key: String, count: Int)]
    let qsosByCountry: [(country: String, flag: String, count: Int)]
    let qsosByHour: [(hour: Int, count: Int)]
    let activitySeries: [(date: Date, count: Int)]

    // SNR
    let avgSnrReceived: Double?
    let snrBuckets: [(label: String, count: Int)]
}

// MARK: - StatisticsEngine

enum StatisticsEngine {

    static func compute(entries: [LogEntry], period: StatsPeriod) -> StatisticsSummary {
        let filtered = Self.filter(entries, period: period)
        return StatisticsSummary(
            totalQSOs: filtered.count,
            uniqueCallsigns: Self.uniqueCount(filtered, keyPath: \.callsign),
            uniqueCountries: Self.uniqueCountryCount(filtered),
            uniqueGrids: Self.uniqueCount(filtered, keyPath: \.grid),
            uniqueBands: Self.uniqueCount(filtered, keyPath: \.band),
            firstQSO: filtered.last?.date,   // sorted desc → last is earliest
            latestQSO: filtered.first?.date,
            qsosByBand: Self.groupBySorted(filtered, keyPath: \.band),
            qsosByMode: Self.groupBySorted(filtered, keyPath: \.mode),
            qsosByCountry: Self.topCountries(filtered, limit: 20),
            qsosByHour: Self.byHour(filtered),
            activitySeries: Self.activitySeries(filtered, period: period),
            avgSnrReceived: Self.averageSnr(filtered),
            snrBuckets: Self.snrBuckets(filtered)
        )
    }

    // MARK: - Filtering

    static func filter(_ entries: [LogEntry], period: StatsPeriod) -> [LogEntry] {
        let start = period.startDate()
        let end = period.endDate()

        return entries.filter { entry in
            if let start, entry.date < start { return false }
            if let end, entry.date >= end { return false }
            return true
        }
    }

    // MARK: - Unique counts

    private static func uniqueCount(_ entries: [LogEntry], keyPath: KeyPath<LogEntry, String>) -> Int {
        Set(entries.map { $0[keyPath: keyPath].lowercased() }.filter { !$0.isEmpty }).count
    }

    private static func uniqueCountryCount(_ entries: [LogEntry]) -> Int {
        Set(entries.compactMap { $0.country?.lowercased() }).count
    }

    // MARK: - Group by

    private static func groupBySorted(_ entries: [LogEntry], keyPath: KeyPath<LogEntry, String>) -> [(key: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries {
            let key = entry[keyPath: keyPath]
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts
            .map { (key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Top countries

    private static func topCountries(_ entries: [LogEntry], limit: Int) -> [(country: String, flag: String, count: Int)] {
        var counts: [String: (flag: String, count: Int)] = [:]
        for entry in entries {
            guard let country = entry.country, !country.isEmpty else { continue }
            let flag = entry.flag ?? ""
            counts[country, default: (flag: flag, count: 0)].count += 1
        }
        return counts
            .map { (country: $0.key, flag: $0.value.flag, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - By hour (UTC)

    private static func byHour(_ entries: [LogEntry]) -> [(hour: Int, count: Int)] {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var counts = [Int: Int]()
        for entry in entries {
            let hour = utcCalendar.component(.hour, from: entry.date)
            counts[hour, default: 0] += 1
        }

        // Return all 24 hours for a complete chart
        return (0..<24).map { h in
            (hour: h, count: counts[h, default: 0])
        }
    }

    // MARK: - Activity series

    static func activitySeries(_ entries: [LogEntry], period: StatsPeriod) -> [(date: Date, count: Int)] {
        guard !entries.isEmpty else { return [] }

        let useDaily = Self.shouldUseDailyGranularity(period)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var counts = [Date: Int]()
        for entry in entries {
            let date: Date
            if useDaily {
                date = utcCalendar.startOfDay(for: entry.date)
            } else {
                let comps = utcCalendar.dateComponents([.year, .month], from: entry.date)
                date = utcCalendar.date(from: comps) ?? entry.date
            }
            counts[date, default: 0] += 1
        }

        return counts
            .map { (date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func shouldUseDailyGranularity(_ period: StatsPeriod) -> Bool {
        switch period {
        case .last7Days, .last30Days, .thisMonth:
            return true
        case .custom(let start, let end):
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            return days <= 90
        default:
            return false
        }
    }

    // MARK: - SNR analysis

    private static func averageSnr(_ entries: [LogEntry]) -> Double? {
        let values = entries.compactMap { Self.parseSnr($0.rstRcvd) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }

    static func parseSnr(_ rst: String) -> Double? {
        let trimmed = rst.trimmingCharacters(in: .whitespaces)
        return Double(trimmed)
    }

    private static func snrBuckets(_ entries: [LogEntry]) -> [(label: String, count: Int)] {
        let values = entries.compactMap { Self.parseSnr($0.rstRcvd) }

        // Buckets: < -18, -18…-12, -12…-6, -6…0, 0…+6, +6…+12, > +12
        let ranges: [(label: String, range: ClosedRange<Double>)] = [
            ("< -18",   -100...(-18.01)),
            ("-18…-12", -18...(-12.01)),
            ("-12…-6",  -12...(-6.01)),
            ("-6…0",    -6...(-0.01)),
            ("0…+6",    0...5.99),
            ("+6…+12",  6...11.99),
            ("> +12",   12...100),
        ]

        return ranges.map { bucket in
            let count = values.filter { bucket.range.contains($0) }.count
            return (label: bucket.label, count: count)
        }
    }
}
