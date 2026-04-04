//
//  QRZProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import Foundation
import Combine

// MARK: - Data Structures

public struct QRZUploadResult: Sendable {
    public let success: Bool
    public let errorMessage: String?

    public init(success: Bool, errorMessage: String? = nil) {
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - Protocol

/// Protocol for QRZ Logbook integration.
/// Premium implementation uploads QSOs to QRZ Logbook API v2.
/// Stub returns no-ops for public-only builds.
@MainActor
public protocol QRZServiceProtocol: ObservableObject {
    /// Number of QSOs waiting to be uploaded.
    var pendingCount: Int { get }

    /// Last sync error message, if any.
    var lastError: String? { get }

    /// Whether a sync operation is currently in progress.
    var isSyncing: Bool { get }

    /// Whether a QRZ API key is stored in the Keychain.
    var hasAPIKey: Bool { get }

    /// Upload a single QSO as an ADIF record string.
    func uploadADIF(_ adif: String) async -> QRZUploadResult

    /// Fetch confirmation status for QSOs uploaded since the given date.
    func fetchConfirmations(since date: Date) async -> String?

    /// Save the QRZ API key to the Keychain.
    func saveAPIKey(_ key: String) throws

    /// Remove the QRZ API key from the Keychain.
    func deleteAPIKey()
}

// MARK: - Stub

/// No-op QRZ service used when premium package is not available.
@MainActor
public final class QRZServiceStub: QRZServiceProtocol {
    public static let shared = QRZServiceStub()
    public nonisolated let objectWillChange = ObservableObjectPublisher()

    public var pendingCount: Int { 0 }
    public var lastError: String? { nil }
    public var isSyncing: Bool { false }
    public var hasAPIKey: Bool { false }

    private init() {}

    public func uploadADIF(_ adif: String) async -> QRZUploadResult {
        QRZUploadResult(success: false, errorMessage: "QRZ integration requires Premium")
    }

    public func fetchConfirmations(since date: Date) async -> String? { nil }

    public func saveAPIKey(_ key: String) throws {
        throw NSError(domain: "QRZStub", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "QRZ integration requires Premium"
        ])
    }

    public func deleteAPIKey() {}
}
