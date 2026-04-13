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

    // NEW: Day of week
    let qsosByDayOfWeek: [(day: Int, label: String, count: Int)]  // 1=Sun..7=Sat

    // NEW: Top callsigns
    let topCallsigns: [(callsign: String, count: Int)]

    // NEW: Band × Hour heatmap
    let bandHourHeatmap: [BandHourCell]

    // NEW: Cumulative growth curves
    let countriesOverTime: [(date: Date, cumulative: Int)]
    let gridsOverTime: [(date: Date, cumulative: Int)]
    let callsignsOverTime: [(date: Date, cumulative: Int)]

    // NEW: Distance stats (nil if myGrid unavailable)
    let distanceStats: DistanceStats?
    let bestDX: [(callsign: String, country: String?, grid: String, distanceKm: Double)]
    let distanceByBand: [(band: String, avgKm: Double, maxKm: Double)]

    // NEW: Records / milestones
    let records: StatsRecords

    // NEW: Year-over-year
    let yearOverYear: [YearMonthCount]

    // NEW: Operating streaks
    let longestStreak: Int
    let currentStreak: Int

    // NEW: SNR scatter (TX vs RX)
    let snrScatter: [(txSnr: Double, rxSnr: Double)]

    // NEW: CQ modifier breakdown
    let qsosByCQModifier: [(key: String, count: Int)]

    // NEW: Grid square heatmap (field-level, e.g. "FN" → count)
    let gridFieldHeatmap: [(field: String, count: Int)]

    // NEW: QSO rate
    let qsoRate: [(date: Date, rate: Double)]  // QSOs per hour for active sessions

    // NEW: Continent breakdown
    let qsosByContinent: [(continent: String, count: Int)]
}

// MARK: - Supporting Types

struct BandHourCell: Identifiable {
    let id = UUID()
    let band: String
    let hour: Int
    let count: Int
}

struct DistanceStats {
    let minKm: Double
    let maxKm: Double
    let avgKm: Double
    let totalKm: Double
    let qsoCount: Int
}

struct StatsRecords {
    let busiestDay: (date: Date, count: Int)?
    let busiestHour: (date: Date, count: Int)?
    let firstQSOPerBand: [(band: String, date: Date, callsign: String)]
}

struct YearMonthCount: Identifiable {
    let id = UUID()
    let year: Int
    let month: Int
    let count: Int
}

// MARK: - StatisticsEngine

enum StatisticsEngine {

    static func compute(entries: [LogEntry], period: StatsPeriod, myGrid: String = "") -> StatisticsSummary {
        let filtered = Self.filter(entries, period: period)
        let sortedByDate = filtered.sorted { $0.date < $1.date }

        return StatisticsSummary(
            totalQSOs: filtered.count,
            uniqueCallsigns: Self.uniqueCount(filtered, keyPath: \.callsign),
            uniqueCountries: Self.uniqueCountryCount(filtered),
            uniqueGrids: Self.uniqueCount(filtered, keyPath: \.grid),
            uniqueBands: Self.uniqueCount(filtered, keyPath: \.band),
            firstQSO: sortedByDate.first?.date,
            latestQSO: sortedByDate.last?.date,
            qsosByBand: Self.groupBySorted(filtered, keyPath: \.band),
            qsosByMode: Self.groupBySorted(filtered, keyPath: \.mode),
            qsosByCountry: Self.topCountries(filtered, limit: 20),
            qsosByHour: Self.byHour(filtered),
            activitySeries: Self.activitySeries(filtered, period: period),
            avgSnrReceived: Self.averageSnr(filtered),
            snrBuckets: Self.snrBuckets(filtered),
            qsosByDayOfWeek: Self.byDayOfWeek(filtered),
            topCallsigns: Self.topCallsigns(filtered, limit: 10),
            bandHourHeatmap: Self.bandHourHeatmap(filtered),
            countriesOverTime: Self.cumulativeGrowth(sortedByDate, keyPath: \.country),
            gridsOverTime: Self.cumulativeGrowthRequired(sortedByDate, keyPath: \.grid),
            callsignsOverTime: Self.cumulativeGrowthRequired(sortedByDate, keyPath: \.callsign),
            distanceStats: Self.distanceStats(filtered, myGrid: myGrid),
            bestDX: Self.bestDX(filtered, myGrid: myGrid, limit: 10),
            distanceByBand: Self.distanceByBand(filtered, myGrid: myGrid),
            records: Self.records(filtered),
            yearOverYear: Self.yearOverYear(filtered),
            longestStreak: Self.operatingStreaks(sortedByDate).longest,
            currentStreak: Self.operatingStreaks(sortedByDate).current,
            snrScatter: Self.snrScatter(filtered),
            qsosByCQModifier: Self.cqModifierBreakdown(filtered),
            gridFieldHeatmap: Self.gridFieldHeatmap(filtered),
            qsoRate: Self.qsoRate(sortedByDate),
            qsosByContinent: Self.continentBreakdown(filtered)
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

    // MARK: - Day of week

    private static func byDayOfWeek(_ entries: [LogEntry]) -> [(day: Int, label: String, count: Int)] {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var counts = [Int: Int]()
        for entry in entries {
            let weekday = utcCalendar.component(.weekday, from: entry.date) // 1=Sun
            counts[weekday, default: 0] += 1
        }
        return (1...7).map { d in
            (day: d, label: labels[d - 1], count: counts[d, default: 0])
        }
    }

    // MARK: - Top callsigns

    private static func topCallsigns(_ entries: [LogEntry], limit: Int) -> [(callsign: String, count: Int)] {
        var counts = [String: Int]()
        for entry in entries {
            let cs = entry.callsign.uppercased()
            guard !cs.isEmpty else { continue }
            counts[cs, default: 0] += 1
        }
        return counts
            .map { (callsign: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Band × Hour heatmap

    private static func bandHourHeatmap(_ entries: [LogEntry]) -> [BandHourCell] {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let bandOrder = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
        var counts = [String: Int]()
        for entry in entries {
            let hour = utcCalendar.component(.hour, from: entry.date)
            let key = "\(entry.band)-\(hour)"
            counts[key, default: 0] += 1
        }

        var cells = [BandHourCell]()
        let activeBands = Set(entries.map(\.band)).intersection(bandOrder)
        let sortedBands = bandOrder.filter { activeBands.contains($0) }
        for band in sortedBands {
            for hour in 0..<24 {
                let count = counts["\(band)-\(hour)", default: 0]
                cells.append(BandHourCell(band: band, hour: hour, count: count))
            }
        }
        return cells
    }

    // MARK: - Cumulative growth (for optional String? fields like country)

    private static func cumulativeGrowth(_ sortedEntries: [LogEntry], keyPath: KeyPath<LogEntry, String?>) -> [(date: Date, cumulative: Int)] {
        guard !sortedEntries.isEmpty else { return [] }
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var seen = Set<String>()
        var result = [(date: Date, cumulative: Int)]()
        var lastDate: Date?

        for entry in sortedEntries {
            guard let val = entry[keyPath: keyPath]?.lowercased(), !val.isEmpty else { continue }
            let day = utcCalendar.startOfDay(for: entry.date)
            let isNew = seen.insert(val).inserted
            if isNew || day != lastDate {
                result.append((date: day, cumulative: seen.count))
                lastDate = day
            }
        }
        return result
    }

    // MARK: - Cumulative growth (for non-optional String fields — callsign, grid)

    private static func cumulativeGrowthRequired(_ sortedEntries: [LogEntry], keyPath: KeyPath<LogEntry, String>) -> [(date: Date, cumulative: Int)] {
        guard !sortedEntries.isEmpty else { return [] }
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var seen = Set<String>()
        var result = [(date: Date, cumulative: Int)]()
        var lastDate: Date?

        for entry in sortedEntries {
            let val = entry[keyPath: keyPath].lowercased()
            guard !val.isEmpty else { continue }
            let day = utcCalendar.startOfDay(for: entry.date)
            let isNew = seen.insert(val).inserted
            if isNew || day != lastDate {
                result.append((date: day, cumulative: seen.count))
                lastDate = day
            }
        }
        return result
    }

    // MARK: - Grid → Coordinate helper

    static func gridToCoordinate(_ grid: String) -> (lat: Double, lon: Double)? {
        let chars = Array(grid.uppercased())
        guard chars.count >= 4,
              let lonField = chars[0].asciiValue, lonField >= 65, lonField <= 82,
              let latField = chars[1].asciiValue, latField >= 65, latField <= 82,
              let lonSquare = chars[2].wholeNumberValue,
              let latSquare = chars[3].wholeNumberValue
        else { return nil }

        var lon = Double(lonField - 65) * 20 - 180 + Double(lonSquare) * 2 + 1.0
        var lat = Double(latField - 65) * 10 - 90 + Double(latSquare) + 0.5

        if chars.count >= 6,
           let subLon = Character(String(chars[4])).lowercased().first?.asciiValue,
           let subLat = Character(String(chars[5])).lowercased().first?.asciiValue {
            lon = Double(lonField - 65) * 20 - 180 + Double(lonSquare) * 2
                + Double(subLon - 97) * (5.0 / 60.0) + (2.5 / 60.0)
            lat = Double(latField - 65) * 10 - 90 + Double(latSquare)
                + Double(subLat - 97) * (2.5 / 60.0) + (1.25 / 60.0)
        }

        return (lat: lat, lon: lon)
    }

    // MARK: - Haversine distance

    static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: - Distance stats

    private static func distanceStats(_ entries: [LogEntry], myGrid: String) -> DistanceStats? {
        let distances = Self.computeDistances(entries, myGrid: myGrid)
        guard !distances.isEmpty else { return nil }
        let sorted = distances.sorted()
        let total = sorted.reduce(0.0, +)
        return DistanceStats(
            minKm: sorted.first!,
            maxKm: sorted.last!,
            avgKm: total / Double(sorted.count),
            totalKm: total,
            qsoCount: sorted.count
        )
    }

    private static func computeDistances(_ entries: [LogEntry], myGrid: String) -> [Double] {
        guard let myCoord = gridToCoordinate(myGrid) else { return [] }
        return entries.compactMap { entry in
            guard !entry.grid.isEmpty, let dxCoord = gridToCoordinate(entry.grid) else { return nil }
            let d = haversineKm(lat1: myCoord.lat, lon1: myCoord.lon,
                                lat2: dxCoord.lat, lon2: dxCoord.lon)
            return d > 0 ? d : nil
        }
    }

    // MARK: - Best DX

    private static func bestDX(_ entries: [LogEntry], myGrid: String, limit: Int) -> [(callsign: String, country: String?, grid: String, distanceKm: Double)] {
        guard let myCoord = gridToCoordinate(myGrid) else { return [] }

        var items: [(callsign: String, country: String?, grid: String, distanceKm: Double)] = []
        for entry in entries {
            guard !entry.grid.isEmpty, let dxCoord = gridToCoordinate(entry.grid) else { continue }
            let d = haversineKm(lat1: myCoord.lat, lon1: myCoord.lon,
                                lat2: dxCoord.lat, lon2: dxCoord.lon)
            if d > 0 {
                items.append((callsign: entry.callsign, country: entry.country, grid: entry.grid, distanceKm: d))
            }
        }
        return items.sorted { $0.distanceKm > $1.distanceKm }.prefix(limit).map { $0 }
    }

    // MARK: - Distance by band

    private static func distanceByBand(_ entries: [LogEntry], myGrid: String) -> [(band: String, avgKm: Double, maxKm: Double)] {
        guard let myCoord = gridToCoordinate(myGrid) else { return [] }

        var bandDistances = [String: [Double]]()
        for entry in entries {
            guard !entry.grid.isEmpty, let dxCoord = gridToCoordinate(entry.grid) else { continue }
            let d = haversineKm(lat1: myCoord.lat, lon1: myCoord.lon,
                                lat2: dxCoord.lat, lon2: dxCoord.lon)
            if d > 0 {
                bandDistances[entry.band, default: []].append(d)
            }
        }

        return bandDistances.map { band, distances in
            let avg = distances.reduce(0, +) / Double(distances.count)
            let maxD = distances.max() ?? 0
            return (band: band, avgKm: avg, maxKm: maxD)
        }.sorted { $0.avgKm > $1.avgKm }
    }

    // MARK: - Records / milestones

    private static func records(_ entries: [LogEntry]) -> StatsRecords {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Busiest day
        var dayCounts = [Date: Int]()
        for entry in entries {
            let day = utcCalendar.startOfDay(for: entry.date)
            dayCounts[day, default: 0] += 1
        }
        let busiestDay = dayCounts.max(by: { $0.value < $1.value }).map { (date: $0.key, count: $0.value) }

        // Busiest hour
        var hourCounts = [Date: Int]()
        for entry in entries {
            let comps = utcCalendar.dateComponents([.year, .month, .day, .hour], from: entry.date)
            if let hourDate = utcCalendar.date(from: comps) {
                hourCounts[hourDate, default: 0] += 1
            }
        }
        let busiestHour = hourCounts.max(by: { $0.value < $1.value }).map { (date: $0.key, count: $0.value) }

        // First QSO per band
        let sorted = entries.sorted { $0.date < $1.date }
        var seenBands = Set<String>()
        var firstPerBand: [(band: String, date: Date, callsign: String)] = []
        for entry in sorted {
            guard !entry.band.isEmpty, seenBands.insert(entry.band).inserted else { continue }
            firstPerBand.append((band: entry.band, date: entry.date, callsign: entry.callsign))
        }

        return StatsRecords(busiestDay: busiestDay, busiestHour: busiestHour, firstQSOPerBand: firstPerBand)
    }

    // MARK: - Year-over-year

    private static func yearOverYear(_ entries: [LogEntry]) -> [YearMonthCount] {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var counts = [String: Int]() // "YYYY-MM" → count
        for entry in entries {
            let year = utcCalendar.component(.year, from: entry.date)
            let month = utcCalendar.component(.month, from: entry.date)
            counts["\(year)-\(month)", default: 0] += 1
        }

        return counts.map { key, count in
            let parts = key.split(separator: "-")
            return YearMonthCount(year: Int(parts[0])!, month: Int(parts[1])!, count: count)
        }.sorted { $0.year == $1.year ? $0.month < $1.month : $0.year < $1.year }
    }

    // MARK: - Operating streaks

    static func operatingStreaks(_ sortedEntries: [LogEntry]) -> (longest: Int, current: Int) {
        guard !sortedEntries.isEmpty else { return (0, 0) }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let days = Set(sortedEntries.map { utcCalendar.startOfDay(for: $0.date) }).sorted()
        guard !days.isEmpty else { return (0, 0) }

        var longest = 1
        var current = 1
        let today = utcCalendar.startOfDay(for: Date())

        for i in 1..<days.count {
            let diff = utcCalendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        // Check if current streak includes today or yesterday
        if let lastDay = days.last {
            let daysFromLast = utcCalendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if daysFromLast > 1 {
                current = 0
            }
        }

        return (longest: longest, current: current)
    }

    // MARK: - SNR Scatter (TX vs RX)

    private static func snrScatter(_ entries: [LogEntry]) -> [(txSnr: Double, rxSnr: Double)] {
        entries.compactMap { entry in
            guard let tx = Self.parseSnr(entry.rstSent),
                  let rx = Self.parseSnr(entry.rstRcvd) else { return nil }
            return (txSnr: tx, rxSnr: rx)
        }
    }

    // MARK: - CQ Modifier breakdown

    private static func cqModifierBreakdown(_ entries: [LogEntry]) -> [(key: String, count: Int)] {
        var counts = [String: Int]()
        for entry in entries {
            let modifier = entry.cqModifier?.trimmingCharacters(in: .whitespaces) ?? ""
            let key = modifier.isEmpty ? "Standard CQ" : modifier.uppercased()
            counts[key, default: 0] += 1
        }
        return counts
            .map { (key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Grid field heatmap (2-char field → count)

    private static func gridFieldHeatmap(_ entries: [LogEntry]) -> [(field: String, count: Int)] {
        var counts = [String: Int]()
        for entry in entries {
            let grid = entry.grid.uppercased()
            guard grid.count >= 2 else { continue }
            let field = String(grid.prefix(2))
            guard field.allSatisfy({ $0.isLetter }) else { continue }
            counts[field, default: 0] += 1
        }
        return counts
            .map { (field: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - QSO Rate (QSOs per hour in active sessions)

    private static func qsoRate(_ sortedEntries: [LogEntry]) -> [(date: Date, rate: Double)] {
        guard sortedEntries.count >= 2 else { return [] }
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Group by hour blocks
        var hourCounts = [Date: Int]()
        for entry in sortedEntries {
            let comps = utcCalendar.dateComponents([.year, .month, .day, .hour], from: entry.date)
            if let hourDate = utcCalendar.date(from: comps) {
                hourCounts[hourDate, default: 0] += 1
            }
        }

        return hourCounts
            .map { (date: $0.key, rate: Double($0.value)) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Continent breakdown

    private static func continentBreakdown(_ entries: [LogEntry]) -> [(continent: String, count: Int)] {
        var counts = [String: Int]()
        for entry in entries {
            guard !entry.grid.isEmpty,
                  let coord = gridToCoordinate(entry.grid) else { continue }
            let continent = Self.continentFromCoords(lat: coord.lat, lon: coord.lon)
            counts[continent, default: 0] += 1
        }
        return counts
            .map { (continent: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Rough continent boundaries from lat/lon.
    static func continentFromCoords(lat: Double, lon: Double) -> String {
        if lat > 0 {
            if lon < -25 { return "NA" }
            if lon < 60 { return "EU" }
            return "AS"
        } else {
            if lon < -25 { return "SA" }
            if lon > 100 { return "OC" }
            if lon > 20 && lon <= 100 {
                if lat > -10 { return "AS" }
                return "OC"
            }
            return "AF"
        }
    }
}
