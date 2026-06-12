import Foundation
import Combine
@testable import ft8_ham

// MARK: - Mock QRZ Service

/// Mock QRZServiceProtocol for unit testing.
/// Tracks all calls and returns configurable results.
@MainActor
final class MockQRZService: QRZServiceProtocol {

    // MARK: ObservableObject
    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: Configurable state
    var pendingCount: Int = 0 { didSet { objectWillChange.send() } }
    var lastError: String? = nil
    var isSyncing: Bool = false
    var hasAPIKey: Bool = false

    // MARK: Configurable results
    var uploadResult: QRZUploadResult = QRZUploadResult(success: true)
    var fetchResult: String? = nil
    var saveAPIKeyThrows: Error? = nil

    // MARK: Call tracking
    var uploadADIFCallCount = 0
    var lastUploadedADIF: String? = nil
    var fetchConfirmationsCallCount = 0
    var lastFetchDate: Date? = nil
    var saveAPIKeyCallCount = 0
    var lastSavedAPIKey: String? = nil
    var deleteAPIKeyCallCount = 0

    func uploadADIF(_ adif: String) async -> QRZUploadResult {
        uploadADIFCallCount += 1
        lastUploadedADIF = adif
        return uploadResult
    }

    func fetchConfirmations(since date: Date) async -> String? {
        fetchConfirmationsCallCount += 1
        lastFetchDate = date
        return fetchResult
    }

    func saveAPIKey(_ key: String) throws {
        if let error = saveAPIKeyThrows { throw error }
        saveAPIKeyCallCount += 1
        lastSavedAPIKey = key
        hasAPIKey = true
    }

    func deleteAPIKey() {
        deleteAPIKeyCallCount += 1
        hasAPIKey = false
    }
}

// MARK: - Mock LoTW Service

/// Mock LoTWServiceProtocol for unit testing.
/// Tracks all calls and returns configurable results.
@MainActor
final class MockLoTWService: LoTWServiceProtocol {

    // MARK: ObservableObject
    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: Configurable state
    var pendingCount: Int = 0 { didSet { objectWillChange.send() } }
    var lastError: String? = nil
    var isSyncing: Bool = false
    var hasCertificate: Bool = false
    var hasAccountCredentials: Bool = false

    // MARK: Configurable results
    var uploadResult: LoTWUploadResult = LoTWUploadResult(success: true)
    var fetchResult: String? = nil
    var importCertThrows: Error? = nil
    var saveCredsThrows: Error? = nil

    // MARK: Call tracking
    var uploadADIFCallCount = 0
    var lastUploadedADIF: String? = nil
    var fetchConfirmationsCallCount = 0
    var lastFetchDate: Date? = nil
    var importCertCallCount = 0
    var deleteCertCallCount = 0
    var saveAccountCredsCallCount = 0
    var lastSavedCallsign: String? = nil
    var deleteAccountCredsCallCount = 0

    func uploadADIF(_ adif: String) async -> LoTWUploadResult {
        uploadADIFCallCount += 1
        lastUploadedADIF = adif
        return uploadResult
    }

    func fetchConfirmations(since date: Date) async -> String? {
        fetchConfirmationsCallCount += 1
        lastFetchDate = date
        return fetchResult
    }

    func importCertificate(from url: URL, password: String) async throws {
        if let error = importCertThrows { throw error }
        importCertCallCount += 1
        hasCertificate = true
    }

    func deleteCertificate() {
        deleteCertCallCount += 1
        hasCertificate = false
    }

    func saveAccountCredentials(callsign: String, password: String) throws {
        if let error = saveCredsThrows { throw error }
        saveAccountCredsCallCount += 1
        lastSavedCallsign = callsign
        hasAccountCredentials = true
    }

    func deleteAccountCredentials() {
        deleteAccountCredsCallCount += 1
        hasAccountCredentials = false
    }
}

// MARK: - Mock eQSL Service

/// Mock eQSLServiceProtocol for unit testing.
/// Tracks all calls and returns configurable results.
@MainActor
final class MockEQSLService: eQSLServiceProtocol {

    // MARK: ObservableObject
    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: Configurable state
    var pendingCount: Int = 0 { didSet { objectWillChange.send() } }
    var lastError: String? = nil
    var isSyncing: Bool = false
    var hasCredentials: Bool = false

    // MARK: Configurable results
    var uploadResult: eQSLUploadResult = eQSLUploadResult(success: true)
    var fetchResult: String? = nil
    var saveCredsThrows: Error? = nil

    // MARK: Call tracking
    var uploadADIFCallCount = 0
    var lastUploadedADIF: String? = nil
    var fetchConfirmationsCallCount = 0
    var lastFetchDate: Date? = nil
    var saveCredentialsCallCount = 0
    var lastSavedCallsign: String? = nil
    var deleteCredentialsCallCount = 0

    func uploadADIF(_ adif: String) async -> eQSLUploadResult {
        uploadADIFCallCount += 1
        lastUploadedADIF = adif
        return uploadResult
    }

    func fetchConfirmations(since date: Date) async -> String? {
        fetchConfirmationsCallCount += 1
        lastFetchDate = date
        return fetchResult
    }

    func saveCredentials(callsign: String, password: String) throws {
        if let error = saveCredsThrows { throw error }
        saveCredentialsCallCount += 1
        lastSavedCallsign = callsign
        hasCredentials = true
    }

    func deleteCredentials() {
        deleteCredentialsCallCount += 1
        hasCredentials = false
    }
}
