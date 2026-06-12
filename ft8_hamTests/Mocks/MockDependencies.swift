import Foundation
import Combine
@testable import ft8_ham

// Note: Protocols AudioManaging, MessageDecoding, LogbookManaging, and TimeProviding
// are defined in DependencyInjection.swift in the main app target

// MARK: - Mock Audio Manager

/// Mock audio manager for unit testing.
/// All audio operations are no-ops but track state changes.
final class MockAudioManager: AudioManaging {
    // MARK: - Properties
    var micSampleRate: Double = 44100
    var sampleRate: Double = 12000
    var isPlaying: Bool = false
    var isListening: Bool = false
    
    // MARK: - Publishers
    let audioSamplesPublisher = PassthroughSubject<[Float], Never>()
    let txStatusPublisher = PassthroughSubject<Bool, Never>()
    let rxStatusPublisher = PassthroughSubject<Bool, Never>()
    let audioErrorPublisher = PassthroughSubject<String, Never>()
    let clippingPublisher = PassthroughSubject<Bool, Never>()
    
    // MARK: - Call Tracking
    var startMicInputCallCount = 0
    var stopMicInputCallCount = 0
    var playAudioCallCount = 0
    var stopPlaybackCallCount = 0
    var lastPlayedAudioData: Data?
    var inputGain: Double = 0.3
    
    // MARK: - Methods
    @MainActor
    func startMicInput() {
        startMicInputCallCount += 1
        isListening = true
        rxStatusPublisher.send(true)
    }
    
    @MainActor
    func stopMicInput() {
        stopMicInputCallCount += 1
        isListening = false
        rxStatusPublisher.send(false)
    }
    
    func playAudio(_ audioData: Data) {
        playAudioCallCount += 1
        lastPlayedAudioData = audioData
        isPlaying = true
        txStatusPublisher.send(true)
    }
    
    func stopPlayback() {
        stopPlaybackCallCount += 1
        isPlaying = false
        txStatusPublisher.send(false)
    }
    
    func setInputGain(_ newValue: Double) {
        inputGain = newValue
    }
    
    func getCurrentInputGain() -> Double {
        return inputGain
    }
    
    func cleanup() {
        isListening = false
        isPlaying = false
    }
    
    // MARK: - Test Helpers
    
    /// Simulate receiving audio samples
    func simulateAudioSamples(_ samples: [Float]) {
        audioSamplesPublisher.send(samples)
    }
    
    /// Simulate clipping detection
    func simulateClipping(_ isClipping: Bool) {
        clippingPublisher.send(isClipping)
    }
    
    /// Simulate audio error
    func simulateError(_ message: String) {
        audioErrorPublisher.send(message)
    }
}

// MARK: - Mock Message Decoder

/// Mock message decoder for unit testing FT8/FT4 operations.
final class MockMessageDecoder: MessageDecoding {
    // MARK: - Configuration
    var generatedAudioData: Data?
    var decodedMessages: [[String: Any]] = []
    var decodedMessagesFromURL: [[AnyHashable: Any]] = []
    
    // MARK: - Call Tracking
    var generateFT8CallCount = 0
    var decodeAudioBufferCallCount = 0
    var decodeURLCallCount = 0
    var lastGeneratedMessage: String?
    var lastDecodedData: Data?
    var lastDecodedURL: URL?
    
    // MARK: - Methods
    func generateFT8(_ message: String, frequency: Float, isFT4: Bool, toFile outputURL: URL?) -> Data? {
        generateFT8CallCount += 1
        lastGeneratedMessage = message
        return generatedAudioData ?? Data(repeating: 0, count: 1024)
    }
    
    func decodeAudioBuffer(_ audioData: Data, sampleRate: Double, isFT4: Bool) -> [[String: Any]] {
        decodeAudioBufferCallCount += 1
        lastDecodedData = audioData
        return decodedMessages
    }
    
    func decode(_ input: URL?, isFT4: Bool) -> [[AnyHashable: Any]] {
        decodeURLCallCount += 1
        lastDecodedURL = input
        return decodedMessagesFromURL
    }
    
    // MARK: - Test Helpers
    
    /// Configure mock to return specific decoded messages
    func setDecodedMessages(_ messages: [[String: Any]]) {
        decodedMessages = messages
    }
    
    /// Create a sample FT8 decoded message
    static func sampleFT8Message(
        callsign: String = "W1ABC",
        snr: Int = -10,
        frequency: Double = 1500,
        message: String? = nil
    ) -> [String: Any] {
        return [
            "call": callsign,
            "snr": snr,
            "freq": frequency,
            "msg": message ?? "CQ \(callsign) FN31"
        ]
    }
}

// MARK: - Mock Logbook Manager

/// Mock logbook manager for unit testing.
final class MockLogbookManager: LogbookManaging {
    // MARK: - State
    var entries: [LogEntry] = []
    var savedURL: URL?
    var exportedURL: URL?
    
    // MARK: - Call Tracking
    var loadEntriesCallCount = 0
    var saveInternalLogCallCount = 0
    var saveToADIFCallCount = 0
    var importFromADIFCallCount = 0
    var clearLogbookCallCount = 0
    var lastSavedEntries: [LogEntry]?
    var lastExportedEntries: [LogEntry]?
    var lastImportedURL: URL?
    var lastImportExistingEntries: [LogEntry]?
    var importResult: ImportResult = ImportResult(imported: 0, skipped: 0)
    
    // MARK: - Methods
    func loadEntries() throws -> [LogEntry] {
        loadEntriesCallCount += 1
        return entries
    }
    
    func saveInternalLog(_ qsoList: [LogEntry]) -> URL? {
        saveInternalLogCallCount += 1
        lastSavedEntries = qsoList
        return savedURL
    }
    
    func saveToADIF(_ qsoList: [LogEntry]) -> URL? {
        saveToADIFCallCount += 1
        lastExportedEntries = qsoList
        return exportedURL
    }
    
    func exportToADIF(_ qsoList: [LogEntry]) -> URL? {
        lastExportedEntries = qsoList
        return exportedURL
    }

    func previewADIF(url: URL, existingEntries: [LogEntry]) -> (newEntries: [LogEntry], skipped: Int, error: String?) {
        return ([], 0, nil)
    }

    func commitImport(newEntries: [LogEntry], existingEntries: [LogEntry]) {}

    func importFromADIF(url: URL, existingEntries: [LogEntry]) -> ImportResult {
        importFromADIFCallCount += 1
        lastImportedURL = url
        lastImportExistingEntries = existingEntries
        return importResult
    }
    
    func clearLogbook() {
        clearLogbookCallCount += 1
        entries.removeAll()
    }
    
    func getEmptyADIFURL() -> URL? {
        return URL(fileURLWithPath: "/tmp/empty.adi")
    }

    var hasBackup: Bool { false }

    func restoreFromBackup() throws -> [LogEntry] {
        return []
    }

    func filterEntries(_ entries: [LogEntry], from startDate: Date?, to endDate: Date?) -> [LogEntry] {
        guard startDate != nil || endDate != nil else {
            return entries
        }
        
        return entries.filter { entry in
            if let start = startDate, entry.date < start {
                return false
            }
            if let end = endDate, entry.date > end {
                return false
            }
            return true
        }
    }

    func filterEntriesSince(_ entries: [LogEntry], since date: Date, upTo upperBound: Date) -> [LogEntry] {
        entries.filter { $0.date > date && $0.date <= upperBound }
    }
    
    // MARK: - Test Helpers
    
    /// Add mock entries for testing
    func addEntries(_ newEntries: [LogEntry]) {
        entries.append(contentsOf: newEntries)
    }
    
    /// Configure URLs returned by save/export
    func configureSaveURL(_ url: URL) {
        savedURL = url
    }
    
    func configureExportURL(_ url: URL) {
        exportedURL = url
    }
}

// MARK: - Test Dependency Container

/// Convenience container for creating test dependencies.
struct TestDependencies {
    let audioManager: MockAudioManager
    let messageDecoder: MockMessageDecoder
    let logbookManager: MockLogbookManager
    let timeProvider: MockTimeProvider
    
    init(startTime: Date = Date()) {
        audioManager = MockAudioManager()
        messageDecoder = MockMessageDecoder()
        logbookManager = MockLogbookManager()
        timeProvider = MockTimeProvider(startTime: startTime)
    }
}
