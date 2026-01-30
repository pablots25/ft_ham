//
//  LogbookManager.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 1/1/26.
//

import Foundation
import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let callsign: String
    let grid: String
    let date: Date              // Always UTC instant
    let mode: String
    let band: String
    let rstSent: String
    let rstRcvd: String
}

final class LogbookManager {
    private let appLogger = AppLogger(category: "LOGBK")
    
    private let fileName = "ft8_log.adi"
    private let adifHeader = "ADIF Export from FT8Ham\n<ADIF_VER:5>3.1.4\n<EOH>\n"

    // MARK: - Load entries from disk
    func loadEntries() -> [LogEntry] {
        guard let fileURL = getFileURL(),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        let records = content.components(separatedBy: "<EOR>")
        var loadedEntries: [LogEntry] = []

        for record in records where record.contains("<CALL") {
            loadedEntries.append(parseRecord(record))
        }

        return loadedEntries.reversed()
    }
    
    func saveInternalLog(_ qsoList: [LogEntry]) -> URL? {
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

    // MARK: - ADIF Parsing (UTC)
    private func parseRecord(_ record: String) -> LogEntry {

        let call = extractField(record, field: "CALL")
        let grid = extractField(record, field: "GRID")
        let band = extractField(record, field: "BAND")
        let rSent = extractField(record, field: "RST_SENT")
        let rRcvd = extractField(record, field: "RST_RCVD")
        let qsoDateRaw = extractField(record, field: "QSO_DATE")
        let timeOnRaw = extractField(record, field: "TIME_ON")

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

        return LogEntry(
            callsign: call,
            grid: grid,
            date: parsedDate ?? Date(timeIntervalSince1970: 0),
            mode: "FT8",
            band: band,
            rstSent: rSent,
            rstRcvd: rRcvd
        )
    }


    // MARK: - Save QSO list to ADIF (UTC)
    func saveToADIF(_ qsoList: [LogEntry]) -> URL? {
        guard let fileURL = getFileURL() else { return nil }

        if qsoList.isEmpty {
            try? adifHeader.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        let dateFormatter = Self.dateFormatter
        let timeFormatter = Self.timeFormatter

        var adifContent = adifHeader
        for entry in qsoList {
            adifContent += "<CALL:\(entry.callsign.count)>\(entry.callsign) "
            adifContent += "<GRID:\(entry.grid.count)>\(entry.grid) "
            adifContent += "<MODE:3>\(entry.mode) "
            adifContent += "<BAND:\(entry.band.count)>\(entry.band) "
            adifContent += "<RST_SENT:\(entry.rstSent.count)>\(entry.rstSent) "
            adifContent += "<RST_RCVD:\(entry.rstRcvd.count)>\(entry.rstRcvd) "
            adifContent += "<QSO_DATE:8>\(dateFormatter.string(from: entry.date)) "
            adifContent += "<TIME_ON:6>\(timeFormatter.string(from: entry.date)) "
            adifContent += "<EOR>\n"
        }

        do {
            try adifContent.write(to: fileURL, atomically: true, encoding: .utf8)
            appLogger.info("Successfully saved \(qsoList.count) entries to ADIF (UTC)")
            return fileURL
        } catch {
            appLogger.error("Failed to save ADIF: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers
    private func getFileURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }
    
    func getEmptyADIFURL() -> URL {
        let url = getFileURL()!
        if !FileManager.default.fileExists(atPath: url.path) {
            try? adifHeader.write(to: url, atomically: true, encoding: .utf8)
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
