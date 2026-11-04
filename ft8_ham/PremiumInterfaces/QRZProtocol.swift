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
    /// QRZ-assigned integer record ID returned by the INSERT action.
    /// Nil when the upload failed or when the API does not return a LOGID.
    public let logID: Int?

    public init(success: Bool, errorMessage: String? = nil, logID: Int? = nil) {
        self.success = success
        self.errorMessage = errorMessage
        self.logID = logID
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
