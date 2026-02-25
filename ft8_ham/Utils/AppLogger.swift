//
//  AppLogger.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import Foundation
import OSLog
import Combine
import FirebaseCrashlytics

enum LogLevel: String, CaseIterable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case debug = "DEBUG"
}

struct LogConfiguration {
    
    static let shared = LogConfiguration()
    
    /// Set of enabled log levels.
    /// In DEBUG builds, all levels are enabled by default.
    /// In RELEASE builds, DEBUG level is disabled by default.
    let enabledLevels: Set<LogLevel>
    
    private init() {
        #if DEBUG
        enabledLevels = Set(LogLevel.allCases)
        #else
        enabledLevels = [.info, .error]
        #endif
    }
    
    /// Returns true if the given log level is enabled.
    func isEnabled(_ level: LogLevel) -> Bool {
        enabledLevels.contains(level)
    }
}

struct AppLogger {
    static let shared = AppLogger(category: "GENERAL")
    
    private let logger: Logger
    private let category: String

    init(subsystem: String = "ft8_ham", category: String) {
        self.category = category
        logger = Logger(subsystem: subsystem, category: category)
    }

    private func timestamp() -> String {
        DateFormatter.utcISOFormatter.string(from: Date())
    }
    
    /// Sanitize message by removing callsigns and grid locators before sending to Crashlytics
    /// Keeps original message for local logging
    private func sanitize(_ message: String) -> String {
        var sanitized = message
        
        // Remove amateur radio callsigns (e.g., EA4IQL, K1ABC, G0XYZ, etc.)
        // Pattern: 1-2 alphanumeric prefix + digit + 1-4 alphanumeric suffix
        let callsignPattern = "\\b[A-Z0-9]{1,2}[0-9][A-Z0-9]{1,4}\\b"
        sanitized = sanitized.replacingOccurrences(
            of: callsignPattern,
            with: "[CALLSIGN]",
            options: .regularExpression
        )
        
        // Remove grid locators (e.g., FN42, JO62ab)
        // Pattern: 2 letters + 2 digits + optional 2 letters
        let gridPattern = "\\b[A-R]{2}[0-9]{2}([a-x]{2})?\\b"
        sanitized = sanitized.replacingOccurrences(
            of: gridPattern,
            with: "[GRID]",
            options: [.regularExpression, .caseInsensitive]
        )
        
        return sanitized
    }

    func log(_ level: LogLevel, _ message: String) {
        guard LogConfiguration.shared.isEnabled(level) else {
            return
        }
        
        let msg = "[\(timestamp())] [\(category)] [\(level.rawValue)]: \(message)"
        
        switch level {
        case .info:
            logger.info("\(msg)")
        case .warning:
            logger.warning("\(msg)")
            #if !DEBUG
            // Log warnings to Crashlytics with sanitized message
            let sanitizedMsg = "[\(timestamp())] [\(category)] [\(level.rawValue)]: \(sanitize(message))"
            Crashlytics.crashlytics().log(sanitizedMsg)
            #endif
        case .error:
            logger.error("\(msg)")
            #if !DEBUG
            // Record errors as non-fatal in Crashlytics with sanitized message
            let sanitizedMessage = sanitize(message)
            let error = NSError(
                domain: "ft8_ham.\(category)",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: sanitizedMessage,
                    "category": category,
                    "timestamp": timestamp()
                ]
            )
            Crashlytics.crashlytics().record(error: error)
            #endif
        case .debug:
            logger.debug("\(msg)")
        }
        
        LogStore.shared.append(msg)
    }

    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }
    func debug(_ message: String) { log(.debug, message) }
    
    /// Record a Swift Error to Crashlytics with additional context
    func recordError(_ error: Error, context: String? = nil) {
        let errorMessage = context.map { "\($0): \(error.localizedDescription)" } 
            ?? error.localizedDescription
        
        let msg = "[\(timestamp())] [\(category)] [ERROR]: \(errorMessage)"
        logger.error("\(msg)")
        
        #if !DEBUG
        // Sanitize error message and context before sending to Crashlytics
        let sanitizedMessage = sanitize(errorMessage)
        let sanitizedContext = context.map { sanitize($0) }
        
        // Record to Crashlytics with sanitized context
        let nsError = error as NSError
        let wrappedError = NSError(
            domain: nsError.domain.isEmpty ? "ft8_ham.\(category)" : nsError.domain,
            code: nsError.code,
            userInfo: [
                NSLocalizedDescriptionKey: sanitizedMessage,
                NSUnderlyingErrorKey: error,
                "category": category,
                "context": sanitizedContext ?? "N/A",
                "timestamp": timestamp()
            ]
        )
        Crashlytics.crashlytics().record(error: wrappedError)
        #endif
        LogStore.shared.append(msg)
    }

    func event(
        _ level: LogLevel,
        _ name: String,
        _ fields: [String: CustomStringConvertible] = [:]
    ) {
        let payload = fields
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        log(level, "\(name) \(payload)")
    }
}

final class LogStore: ObservableObject {
    static let shared = LogStore()
    
    @Published private(set) var logs: [String] = []
    private let maxEntries = 1000
    private let queue = DispatchQueue(label: "com.ft8-ham.logstore", attributes: .concurrent)
    
    private init() {}
    
    func append(_ message: String) {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.logs.append(message)
                if self.logs.count > self.maxEntries {
                    self.logs.removeFirst()
                }
            }
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.logs.removeAll()
            }
        }
    }
}
