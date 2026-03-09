//
//  DependencyInjection.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/2/26.
//
//  Protocols and utilities for dependency injection to improve testability.
//

import Combine
import Foundation

// MARK: - App Environment

/// Centralized detection of app execution environment.
/// Use this instead of scattered ProcessInfo checks throughout the codebase.
enum AppEnvironment {
    case production
    case preview
    case unitTest
    
    static let current: AppEnvironment = {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .preview
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .unitTest
        }
        return .production
    }()
    
    var isPreview: Bool { self == .preview }
    var isUnitTest: Bool { self == .unitTest }
    var isProduction: Bool { self == .production }
    var shouldDisableAudio: Bool { self != .production }
}

// MARK: - Time Provider Protocol

/// Protocol for time-related operations. Allows injecting mock time for deterministic tests.
protocol TimeProviding: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

/// Default implementation using system time.
struct SystemTimeProvider: TimeProviding {
    var now: Date { Date() }
    
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Mock time provider for unit tests - allows controlling time flow.
final class MockTimeProvider: TimeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _currentTime: Date
    
    init(startTime: Date = Date()) {
        _currentTime = startTime
    }
    
    var now: Date {
        lock.withLock { _currentTime }
    }
    
    func sleep(for duration: Duration) async throws {
        // In tests, we can advance time instantly or simulate delays
        advance(by: duration.timeInterval)
    }
    
    /// Advance time by specified interval
    func advance(by interval: TimeInterval) {
        lock.withLock {
            _currentTime = _currentTime.addingTimeInterval(interval)
        }
    }
    
    /// Set time to specific date
    func setTime(_ date: Date) {
        lock.withLock {
            _currentTime = date
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }
}

// MARK: - Audio Managing Protocol

/// Protocol for audio input/output operations.
/// Implement this protocol for mocking audio in tests.
protocol AudioManaging: AnyObject {
    // MARK: - Properties
    var micSampleRate: Double { get }
    var sampleRate: Double { get }
    var isPlaying: Bool { get }
    var isListening: Bool { get }
    
    // MARK: - Publishers
    var audioSamplesPublisher: PassthroughSubject<[Float], Never> { get }
    var txStatusPublisher: PassthroughSubject<Bool, Never> { get }
    var rxStatusPublisher: PassthroughSubject<Bool, Never> { get }
    var audioErrorPublisher: PassthroughSubject<String, Never> { get }
    var clippingPublisher: PassthroughSubject<Bool, Never> { get }
    
    // MARK: - Methods
    @MainActor func startMicInput()
    @MainActor func stopMicInput()
    func playAudio(_ audioData: Data)
    func stopPlayback()
    func setInputGain(_ newValue: Double)
    func getCurrentInputGain() -> Double
    func cleanup()
}

// MARK: - Message Decoding Protocol

/// Protocol for FT8/FT4 message encoding and decoding.
protocol MessageDecoding: AnyObject {
    func generateFT8(_ message: String, frequency: Float, isFT4: Bool, toFile outputURL: URL?) -> Data?
    func decodeAudioBuffer(_ audioData: Data, sampleRate: Double, isFT4: Bool) -> [[String: Any]]
    func decode(_ input: URL?, isFT4: Bool) -> [[AnyHashable: Any]]
}

// MARK: - Logbook Managing Protocol

/// Protocol for logbook operations.
protocol LogbookManaging {
    func loadEntries() -> [LogEntry]
    func saveInternalLog(_ qsoList: [LogEntry]) -> URL?
    func saveToADIF(_ qsoList: [LogEntry]) -> URL?
    func exportToADIF(_ qsoList: [LogEntry]) -> URL?
    func clearLogbook()
    func getEmptyADIFURL() -> URL
    func filterEntries(_ entries: [LogEntry], from startDate: Date?, to endDate: Date?) -> [LogEntry]
    func filterEntriesSince(_ entries: [LogEntry], since date: Date, upTo upperBound: Date) -> [LogEntry]
}

// MARK: - Dependency Container

/// Container for injecting dependencies in tests or previews.
/// Use this to override default implementations.
@MainActor
final class DependencyContainer {
    // Singleton for app-wide access, but can be replaced in tests
    static var shared = DependencyContainer()
    
    var timeProvider: TimeProviding = SystemTimeProvider()
    var environment: AppEnvironment = .current
    
    /// Reset to defaults - useful for test teardown
    func reset() {
        timeProvider = SystemTimeProvider()
        environment = .current
    }
}

// MARK: - Protocol Extensions for Default Implementations

extension AudioManaging {
    /// Default no-op for optional methods
    func cleanup() {}
}

// MARK: - ft8_Engine Conformance to MessageDecoding

extension ft8_Engine: MessageDecoding {
    func decodeAudioBuffer(_ audioData: Data, sampleRate: Double, isFT4: Bool) -> [[String: Any]] {
        // Bridge Objective-C method to Swift protocol
        let result = self.decodeBuffer(usingMonitor: audioData, sampleRate: sampleRate, isFT4: isFT4)
        return result as? [[String: Any]] ?? []
    }
}
