//
//  eQSLProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/04/26.
//

import Foundation
import Combine

// MARK: - Data Structures

public struct eQSLUploadResult: Sendable {
    public let success: Bool
    public let errorMessage: String?

    public init(success: Bool, errorMessage: String? = nil) {
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - Protocol

/// Protocol for eQSL.cc integration.
/// Premium implementation uploads QSOs via HTTP multipart POST to eQSL.cc.
/// Stub returns no-ops for public-only builds.
@MainActor
public protocol eQSLServiceProtocol: ObservableObject {
    /// Number of QSOs waiting to be uploaded.
    var pendingCount: Int { get }

    /// Last sync error message, if any.
    var lastError: String? { get }

    /// Whether a sync operation is currently in progress.
    var isSyncing: Bool { get }

    /// Whether eQSL credentials (callsign + password) are stored in the Keychain.
    var hasCredentials: Bool { get }

    /// Upload a single QSO as an ADIF record string.
    func uploadADIF(_ adif: String) async -> eQSLUploadResult

    /// Fetch eQSL confirmations (not available via API — always returns nil).
    func fetchConfirmations(since date: Date) async -> String?

    /// Save eQSL credentials to the Keychain.
    func saveCredentials(callsign: String, password: String) throws

    /// Remove eQSL credentials from the Keychain.
    func deleteCredentials()
}

// MARK: - Stub

/// No-op eQSL service used when premium package is not available.
@MainActor
public final class eQSLServiceStub: eQSLServiceProtocol {
    nonisolated(unsafe) public static let shared = eQSLServiceStub()
    public nonisolated let objectWillChange = ObservableObjectPublisher()

    public var pendingCount: Int { 0 }
    public var lastError: String? { nil }
    public var isSyncing: Bool { false }
    public var hasCredentials: Bool { false }

    nonisolated private init() {}

    public func uploadADIF(_ adif: String) async -> eQSLUploadResult {
        eQSLUploadResult(success: false, errorMessage: "eQSL integration requires Premium")
    }

    public func fetchConfirmations(since _: Date) async -> String? { nil }

    public func saveCredentials(callsign: String, password: String) throws {
        throw NSError(domain: "eQSLStub", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "eQSL integration requires Premium"
        ])
    }

    public func deleteCredentials() {}
}
