//
//  LogbookRowViews.swift
//  ft_ham
//
//  Created by Pablo Turrion on 1/1/26.
//

import SwiftUI

// MARK: - LogbookCompactRow

struct LogbookCompactRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.callsign)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.grid)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let flag = entry.flag {
                    Text(flag).font(.subheadline)
                }
                if let country = entry.country, !country.isEmpty {
                    Text(country)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if !entry.mode.isEmpty {
                    Text(entry.mode)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(LogbookBadgeColors.mode(entry.mode).opacity(0.2))
                        .cornerRadius(5)
                }
                if entry.band != "Unknown" && !entry.band.isEmpty {
                    Text(entry.band)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(LogbookBadgeColors.band(entry.band).opacity(0.2))
                        .cornerRadius(5)
                }
            }
        }
    }
}

// MARK: - LogbookExpandedRow

struct LogbookExpandedRow: View {
    let entry: LogEntry
    let displayLocalTime: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {

                // Row 1: callsign + flag + country
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.callsign)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let flag = entry.flag {
                        Text(flag).font(.headline)
                    }
                    if let country = entry.country, !country.isEmpty {
                        Text(country)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                // Row 2: grid + SNR
                HStack {
                    Text(entry.grid)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        Text("SNR:").font(.caption).foregroundStyle(.primary)
                        Text(entry.rstSent).font(.caption).foregroundStyle(.primary)
                        Text("(TX)").font(.caption).foregroundStyle(.secondary)
                        Text("/").font(.caption).foregroundStyle(.primary)
                        Text(entry.rstRcvd).font(.caption).foregroundStyle(.primary)
                        Text("(RX)").font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }

                // Row 3: station + frequency
                HStack {
                    if let station = entry.stationCallsign, !station.isEmpty {
                        Text("Station: \(station)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    if let hz = entry.frequencyHz {
                        Text(String(format: "%.3f MHz", hz / 1_000_000))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Row 4: cq modifier + date/time
                if entry.cqModifier != nil || entry.frequencyHz != nil {
                    HStack {
                        if let cqModifier = entry.cqModifier, !cqModifier.isEmpty {
                            Group {
                                if let sigInfo = entry.mySigInfo, !sigInfo.isEmpty {
                                    Text("\(cqModifier): \(sigInfo)")
                                } else {
                                    Text(cqModifier)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 4) {
                            Text(LogbookRowFormatters.dateString(from: entry.date, local: displayLocalTime))
                            Text(LogbookRowFormatters.timeString(from: entry.date, local: displayLocalTime))
                            if displayLocalTime { Text("(Local)") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }

            // Badges column
            VStack(alignment: .trailing) {
                Spacer(minLength: 0)
                if !entry.mode.isEmpty {
                    Text(entry.mode)
                        .font(.caption)
                        .frame(width: 36)
                        .padding(.vertical, 4)
                        .background(LogbookBadgeColors.mode(entry.mode).opacity(0.2))
                        .cornerRadius(6)
                }
                Spacer(minLength: 0)
                if entry.band != "Unknown" && !entry.band.isEmpty {
                    Text(entry.band)
                        .font(.caption)
                        .frame(width: 36)
                        .padding(.vertical, 4)
                        .background(LogbookBadgeColors.band(entry.band).opacity(0.2))
                        .cornerRadius(6)
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Badge Color Helpers

enum LogbookBadgeColors {
    static func mode(_ mode: String) -> Color {
        switch mode.uppercased() {
        case "FT8": return .green
        case "FT4": return .blue
        default:    return .gray
        }
    }

    static func band(_ band: String) -> Color {
        switch band {
        case "160m":   return .purple
        case "80m":    return Color(red: 0.5, green: 0.0, blue: 0.5)
        case "60m":    return .indigo
        case "40m":    return .blue
        case "30m":    return .teal
        case "20m":    return .green
        case "17m":    return .cyan
        case "15m":    return .yellow
        case "12m":    return .orange
        case "CB/11m": return .gray
        case "10m":    return .red
        case "6m":     return .pink
        case "Custom": return .mint
        default:       return .blue
        }
    }
}

// MARK: - Date/Time Formatters (shared, static)

enum LogbookRowFormatters {
    private static let utcDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    private static let utcTime: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "HH:mm:ss 'UTC'"
        return f
    }()

    private static let localDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    private static let localTime: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func dateString(from date: Date, local: Bool) -> String {
        local ? localDate.string(from: date) : utcDate.string(from: date)
    }

    static func timeString(from date: Date, local: Bool) -> String {
        local ? localTime.string(from: date) : utcTime.string(from: date)
    }
}

// MARK: - LogbookRowCell

struct LogbookRowCell: View {
    let entry: LogEntry
    let isExpanded: Bool
    let displayLocalTime: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Group {
            if isExpanded {
                LogbookExpandedRow(entry: entry, displayLocalTime: displayLocalTime)
            } else {
                LogbookCompactRow(entry: entry)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

// MARK: - Previews

#Preview("Compact Row") {
    List {
        LogbookCompactRow(entry: PreviewMocks.qsoList[0])
    }
    .listStyle(.plain)
}

#Preview("Expanded Row") {
    List {
        LogbookExpandedRow(entry: PreviewMocks.qsoList[0], displayLocalTime: false)
    }
    .listStyle(.plain)
}
