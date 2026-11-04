//
//  LoTWProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import Foundation
import Combine

// MARK: - Data Structures

public struct LoTWUploadResult: Sendable {
    public let success: Bool
    public let errorMessage: String?

    public init(success: Bool, errorMessage: String? = nil) {
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - Protocol

/// Protocol for LoTW (Logbook of the World) integration.
/// Premium implementation signs ADIF records with a .p12 certificate and uploads via ARRL API.
/// Stub returns no-ops for public-only builds.
@MainActor
public protocol LoTWServiceProtocol: ObservableObject {
    /// Number of QSOs waiting to be uploaded.
    var pendingCount: Int { get }

    /// Last sync error message, if any.
    var lastError: String? { get }

    /// Whether a sync operation is currently in progress.
    var isSyncing: Bool { get }

    /// Whether a valid .p12 certificate is stored in the Keychain.
    var hasCertificate: Bool { get }

    /// Whether LoTW account credentials (callsign + password) are stored in the Keychain.
    var hasAccountCredentials: Bool { get }

    /// Upload a single QSO as a signed ADIF record string.
    func uploadADIF(_ adif: String) async -> LoTWUploadResult

    /// Fetch confirmations from LoTW using stored Keychain credentials.
    func fetchConfirmations(since date: Date) async -> String?

    /// Import a .p12 certificate from the given URL and store it in the Keychain.
    func importCertificate(from url: URL, password: String) async throws

    /// Remove the .p12 certificate from the Keychain.
    func deleteCertificate()

    /// Save LoTW account credentials (callsign + password) to the Keychain.
    func saveAccountCredentials(callsign: String, password: String) throws

    /// Remove LoTW account credentials from the Keychain.
    func deleteAccountCredentials()
}
