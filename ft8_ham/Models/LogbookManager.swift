//
//  LogbookManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 1/1/26.
//

import Foundation
import SwiftUI

// MARK: - Log Sync Status

/// Upload/confirmation status for a single QSO in an external logbook service.
/// ✗ local → ✓ uploaded → ★ confirmed
enum LogSyncStatus: String, Codable, Sendable {
    case notUploaded   // QSO exists only locally
    case pending       // Queued for upload; network unavailable or retry in progress
    case uploaded      // Successfully delivered to remote service
    case confirmed     // Remote service confirmed the QSO (award credit)
    case duplicate     // Remote service rejected as duplicate
    case rejected      // Remote service rejected with a permanent error
}

// MARK: - ImportResult

struct ImportResult {
    let imported: Int
    let skipped: Int
    let error: String?

    /// Number of entries skipped because they were duplicates of existing entries.
    var duplicates: Int { skipped }

    init(imported: Int, skipped: Int, error: String? = nil) {
        self.imported = imported
        self.skipped = skipped
        self.error = error
    }
}

// MARK: - LogbookError

enum LogbookError: Error, LocalizedError {
    case noBackupAvailable
    var errorDescription: String? {
        switch self {
        case .noBackupAvailable:
            return "No backup file is available to restore from."
        }
    }
}

// MARK: - LogEntry

struct LogEntry: Identifiable {
    let id: UUID
    let callsign: String
    let grid: String
    let date: Date              // Always UTC instant
    let frequencyHz: Double?
    let mode: String
    let band: String
    let rstSent: String
    let rstRcvd: String
    let stationCallsign: String?
    let cqModifier: String?
    let mySigInfo: String?
    let country: String?        // Resolved country name from CountryResolver
    let flag: String?           // Cached flag emoji for performance

    // MARK: Sync Status
    var qrzStatus: LogSyncStatus
    var lotwStatus: LogSyncStatus

    init(
        id: UUID = UUID(),
        callsign: String,
        grid: String,
        date: Date,
        frequencyHz: Double?,
        mode: String,
        band: String,
        rstSent: String,
        rstRcvd: String,
        stationCallsign: String?,
        cqModifier: String?,
        mySigInfo: String?,
        country: String?,
        flag: String?,
        qrzStatus: LogSyncStatus = .notUploaded,
        lotwStatus: LogSyncStatus = .notUploaded
    ) {
        self.id = id
        self.callsign = callsign
        self.grid = grid
        self.date = date
        self.mode = mode
        self.band = band
        self.rstSent = rstSent
        self.rstRcvd = rstRcvd
        self.stationCallsign = stationCallsign
        self.cqModifier = cqModifier
        self.mySigInfo = mySigInfo
        self.country = country
        self.flag = flag
        self.frequencyHz = frequencyHz
        self.qrzStatus = qrzStatus
        self.lotwStatus = lotwStatus
    }
}

final class LogbookManager: LogbookManaging {
    private let appLogger = AppLogger(category: "LOGBK")
    
    private let persistentFileName = "ft8_log.adi"
    private let backupFileName = "ft8_log.adi.bak"
    private let adifHeader = "ADIF Export from FT8Ham\n<ADIF_VER:5>3.1.4\n<EOH>\n"

    var hasBackup: Bool {
        guard let backupURL = getBackupURL() else { return false }
        return FileManager.default.fileExists(atPath: backupURL.path)
    }
    
    // MARK: - Export filename with timestamp (for user exports)
    private var exportFileName: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmm"

        let timestamp = formatter.string(from: Date())
        return "FT_HAM_Log_\(timestamp).adif"
    }
    
    // MARK: - Filtering
    func filterEntries(_ entries: [LogEntry], from startDate: Date?, to endDate: Date?) -> [LogEntry] {
        var filtered = entries
        
        if let start = startDate {
            // Start of the start date (00:00:00 UTC)
            let calendar = Calendar(identifier: .gregorian)
            var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: start)
            components.hour = 0
            components.minute = 0
            components.second = 0
            if let startOfDay = calendar.date(from: components) {
                filtered = filtered.filter { $0.date >= startOfDay }
            }
        }
        
        if let end = endDate {
            // End of the end date (23:59:59 UTC)
            let calendar = Calendar(identifier: .gregorian)
            var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: end)
            components.hour = 23
            components.minute = 59
            components.second = 59
            if let endOfDay = calendar.date(from: components) {
                filtered = filtered.filter { $0.date <= endOfDay }
            }
        }
        
        return filtered
    }

    func filterEntriesSince(_ entries: [LogEntry], since date: Date, upTo upperBound: Date = Date()) -> [LogEntry] {
        entries.filter { $0.date > date && $0.date <= upperBound }
    }

    // MARK: - Load entries from disk
    func loadEntries() throws -> [LogEntry] {
        guard let fileURL = getFileURL() else { return [] }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        let records = content.components(separatedBy: "<EOR>")
        var loadedEntries: [LogEntry] = []

        for record in records where record.contains("<CALL") {
            loadedEntries.append(parseRecord(record))
        }

        return loadedEntries.reversed()
    }
    
    func saveInternalLog(_ qsoList: [LogEntry]) -> URL? {
        createBackup()
        return saveToADIF(qsoList)
    }

    // MARK: - Clear logbook (disk + header reset)
    func clearLogbook() {
        guard let fileURL = getFileURL() else { return }
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                appLogger.info("Removed existing ADIF log file")
            }
            
            try adifHeader.write(to: fileURL, atomically: true, encoding: .utf8)
            appLogger.info("Recreated empty ADIF log with header")
        } catch {
            appLogger.error("Failed to clear logbook: \(error.localizedDescription)")
        }
    }

    // MARK: - Backup & Restore

    private func createBackup() {
        guard let fileURL = getFileURL(),
              let backupURL = getBackupURL(),
              FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            appLogger.info("Created logbook backup")
        } catch {
            appLogger.error("Failed to create logbook backup: \(error.localizedDescription)")
        }
    }

    func restoreFromBackup() throws -> [LogEntry] {
        guard let backupURL = getBackupURL(),
              let fileURL = getFileURL() else {
            throw LogbookError.noBackupAvailable
        }
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw LogbookError.noBackupAvailable
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.copyItem(at: backupURL, to: fileURL)
        appLogger.info("Restored logbook from backup")
        return try loadEntries()
    }

    // MARK: - ADIF Parsing (UTC)
    private func parseRecord(_ record: String) -> LogEntry {

        let call = extractField(record, field: "CALL")
        let grid = extractField(record, field: "GRID")
        let band = extractField(record, field: "BAND")
        let rSent = extractField(record, field: "RST_SENT")
        let rRcvd = extractField(record, field: "RST_RCVD")
        let mySig = extractField(record, field: "MY_SIG")
        let mySigInfo = extractField(record, field: "MY_SIG_INFO")
        let stationCall = extractField(record, field: "STATION_CALLSIGN")
        let qsoDateRaw = extractField(record, field: "QSO_DATE")
        let timeOnRaw = extractField(record, field: "TIME_ON")
        let freqRaw = extractField(record, field: "FREQ")
        let modeRaw = extractField(record, field: "MODE").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let qsoDate = qsoDateRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeOnClean = timeOnRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter(\.isNumber)

        var parsedDate: Date?

        if qsoDate.count == 8 {

            let normalizedTime: String

            switch timeOnClean.count {
            case 4: // HHmm
                normalizedTime = timeOnClean + "00"
            case 6: // HHmmss
                normalizedTime = timeOnClean
            default:
                normalizedTime = ""
            }

            if normalizedTime.count == 6 {
                parsedDate = Self.dateTimeFormatterHHmmss
                    .date(from: qsoDate + normalizedTime)
            }
        }

        if parsedDate == nil {
            appLogger.warning(
                "Failed to parse QSO date for CALL \(call). Falling back to epoch."
            )
        }

        let parsedFrequencyHz: Double? = {
            let clean = freqRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, let mhz = Double(clean), mhz > 0 else { return nil }
            return mhz * 1_000_000
        }()

        let mode = ["FT8", "FT4"].contains(modeRaw) ? modeRaw : "FT8"

        return LogEntry(
            callsign: call,
            grid: grid,
            date: parsedDate ?? Date(timeIntervalSince1970: 0),
            frequencyHz: parsedFrequencyHz,
            mode: mode,
            band: band,
            rstSent: rSent,
            rstRcvd: rRcvd,
            stationCallsign: stationCall.isEmpty ? nil : stationCall,
            cqModifier: mySig.isEmpty ? nil : mySig,
            mySigInfo: mySigInfo.isEmpty ? nil : mySigInfo,
            country: CountryResolver.countryAndCoordinates(for: call).country,
            flag: FlagUtility.flag(for: CountryResolver.countryAndCoordinates(for: call).country)
        )
    }


    // MARK: - Import from external ADIF file
    func importFromADIF(url: URL, existingEntries: [LogEntry]) -> ImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            let message = "Could not read the ADIF file: \(error.localizedDescription)"
            appLogger.error("importFromADIF: failed to read file at \(url.lastPathComponent): \(error.localizedDescription)")
            return ImportResult(imported: 0, skipped: 0, error: message)
        }

        // Normalise <EOR> tag casing before splitting
        let normalised = content.replacingOccurrences(of: "<eor>", with: "<EOR>", options: .caseInsensitive)
        let rawRecords = normalised.components(separatedBy: "<EOR>")

        var newEntries: [LogEntry] = []
        var skipped = 0

        for record in rawRecords where record.lowercased().contains("<call") {
            let entry = parseRecord(record)
            if isDuplicate(entry, in: existingEntries) {
                skipped += 1
            } else {
                newEntries.append(entry)
            }
        }

        if !newEntries.isEmpty {
            _ = saveToADIF(existingEntries + newEntries)
        }

        appLogger.info("importFromADIF: \(newEntries.count) imported, \(skipped) skipped")
        return ImportResult(imported: newEntries.count, skipped: skipped)
    }

    private func isDuplicate(_ entry: LogEntry, in existing: [LogEntry]) -> Bool {
        existing.contains { e in
            e.callsign == entry.callsign &&
            e.band == entry.band &&
            abs(e.date.timeIntervalSince(entry.date)) < 120
        }
    }

    // MARK: - Save QSO list to ADIF (UTC)
    func saveToADIF(_ qsoList: [LogEntry]) -> URL? {
        guard let fileURL = getFileURL() else { return nil }
        return writeADIF(qsoList, to: fileURL, operationName: "save")
    }

    // MARK: - Helpers
    private func adifFields(for entry: LogEntry) -> [String: String] {
        var fields: [String: String] = [:]

        if let mod = entry.cqModifier?.trimmingCharacters(in: .whitespacesAndNewlines), !mod.isEmpty {
            // MY_SIG is for activation designators (POTA, SOTA, WWFF, IOTA) and custom modifiers.
            // Geographic/directional modifiers (DX, EU, NA…) are not MY_SIG values.
            let normalizedMod = mod.uppercased()
            let isGeographic = CQModifier(rawValue: normalizedMod)?.group == .geographic
            if !isGeographic {
                fields["MY_SIG"] = normalizedMod
            }
        }

        // Only emit MY_SIG_INFO when a corresponding MY_SIG is present.
        if fields["MY_SIG"] != nil,
           let sigInfo = entry.mySigInfo?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sigInfo.isEmpty {
            fields["MY_SIG_INFO"] = sigInfo
        }

        return fields
    }

    private func getFileURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(persistentFileName)
    }

    private func getBackupURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(backupFileName)
    }

    private func getExportFileURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(exportFileName)
    }
    
    // MARK: - Export QSO list to ADIF with dynamic filename (for user exports)
    func exportToADIF(_ qsoList: [LogEntry]) -> URL? {
        guard let fileURL = getExportFileURL() else { return nil }
        return writeADIF(qsoList, to: fileURL, operationName: "export")
    }
    
    // MARK: - Private helper to write ADIF content
    private func writeADIF(_ qsoList: [LogEntry], to fileURL: URL, operationName: String) -> URL? {
        if qsoList.isEmpty {
            do {
                try adifHeader.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                appLogger.error("Failed to write ADIF header: \(error.localizedDescription)")
                return nil
            }
            return fileURL
        }

        let adifContent = buildADIFContent(qsoList)

        do {
            try adifContent.write(to: fileURL, atomically: true, encoding: .utf8)
            if operationName == "export" {
                appLogger.info("Successfully exported \(qsoList.count) entries to ADIF with dynamic filename: \(fileURL.lastPathComponent)")
            } else {
                appLogger.info("Successfully saved \(qsoList.count) entries to ADIF (UTC)")
            }
            return fileURL
        } catch {
            appLogger.error("Failed to \(operationName) ADIF: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Build ADIF content from QSO list
    private func buildADIFContent(_ qsoList: [LogEntry]) -> String {
        var adifContent = adifHeader
        let dateFormatter = Self.dateFormatter
        let timeFormatter = Self.timeFormatter
        
        for entry in qsoList {
            adifContent += "<CALL:\(entry.callsign.count)>\(entry.callsign) "
            if let station = entry.stationCallsign, !station.isEmpty {
                adifContent += "<STATION_CALLSIGN:\(station.count)>\(station) "
            }
            if let frequency = adifFrequencyString(fromHz: entry.frequencyHz) {
                adifContent += "<FREQ:\(frequency.count)>\(frequency) "
            }
            if entry.band != "Unknown" && !entry.band.isEmpty {
                adifContent += "<BAND:\(entry.band.count)>\(entry.band) "
            }
            adifContent += "<MODE:3>\(entry.mode) "
            adifContent += "<RST_SENT:\(entry.rstSent.count)>\(entry.rstSent) "
            adifContent += "<RST_RCVD:\(entry.rstRcvd.count)>\(entry.rstRcvd) "
            adifContent += "<QSO_DATE:8>\(dateFormatter.string(from: entry.date)) "
            adifContent += "<TIME_ON:6>\(timeFormatter.string(from: entry.date)) "
            let special = adifFields(for: entry)
            for (key, value) in special {
                adifContent += "<\(key):\(value.count)>\(value) "
            }
            if !entry.grid.isEmpty {
                adifContent += "<GRID:\(entry.grid.count)>\(entry.grid) "
            }
            adifContent += "<EOR>\n"
        }
        
        return adifContent
    }

    private func adifFrequencyString(fromHz frequencyHz: Double?) -> String? {
        guard let frequencyHz, frequencyHz > 0 else { return nil }
        let mhz = frequencyHz / 1_000_000
        return Self.adifFrequencyFormatter.string(from: NSNumber(value: mhz))
    }
    
    func getEmptyADIFURL() -> URL? {
        guard let url = getFileURL() else { return nil }
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try adifHeader.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                appLogger.error("Failed to write empty ADIF header: \(error.localizedDescription)")
                return nil
            }
        }
        return url
    }

    private func extractField(_ text: String, field: String) -> String {
        guard let tagRange = text.range(
            of: "<\(field):[^>]+>",
            options: .regularExpression
        ) else {
            return ""
        }

        let valueStart = tagRange.upperBound
        let remaining = text[valueStart...]

        let value: Substring
        if let nextTag = remaining.firstIndex(of: "<") {
            value = remaining[..<nextTag]
        } else {
            value = remaining
        }

        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    // MARK: - UTC DateFormatters (Single Source of Truth)
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utcTimeZone
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utcTimeZone
        f.dateFormat = "HHmmss"
        return f
    }()

    private static let dateTimeFormatterHHmm: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utcTimeZone
        f.dateFormat = "yyyyMMddHHmm"
        return f
    }()

    private static let dateTimeFormatterHHmmss: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utcTimeZone
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    private static let adifFrequencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 6
        f.maximumFractionDigits = 6
        return f
    }()
}

#if DEBUG
extension LogbookManager {

    func loadEntriesFromString(_ content: String) -> [LogEntry] {
        let records = content.components(separatedBy: "<EOR>")
        var loadedEntries: [LogEntry] = []

        for record in records where record.contains("<CALL") {
            loadedEntries.append(parseRecord(record))
        }

        return loadedEntries
    }

}
#endif
