//
//  AppLogger.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import Foundation
import OSLog
import Combine

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
        case .error:
            logger.error("\(msg)")
        case .debug:
            logger.debug("\(msg)")
        }
        
        LogStore.shared.append(msg)
    }

    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }
    func debug(_ message: String) { log(.debug, message) }

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
    
    private init() {}
    
    func append(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(message)
            if self.logs.count > self.maxEntries {
                self.logs.removeFirst()
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}
