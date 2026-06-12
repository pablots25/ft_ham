//
//  LoTWServiceStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import Foundation
import Combine

/// No-op LoTW service used when premium package is not available.
@MainActor
public final class LoTWServiceStub: LoTWServiceProtocol {
    public static let shared = LoTWServiceStub()
    public nonisolated let objectWillChange = ObservableObjectPublisher()

    public var pendingCount: Int { 0 }
    public var lastError: String? { nil }
    public var isSyncing: Bool { false }
    public var hasCertificate: Bool { false }
    public var hasAccountCredentials: Bool { false }

    private init() {}

    public func uploadADIF(_ adif: String) async -> LoTWUploadResult {
        LoTWUploadResult(success: false, errorMessage: "LoTW integration requires Premium")
    }

    public func fetchConfirmations(since date: Date) async -> String? { nil }

    public func importCertificate(from url: URL, password: String) async throws {
        throw NSError(domain: "LoTWStub", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "LoTW integration requires Premium"
        ])
    }

    public func deleteCertificate() {}

    public func saveAccountCredentials(callsign: String, password: String) throws {
        throw NSError(domain: "LoTWStub", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "LoTW integration requires Premium"
        ])
    }

    public func deleteAccountCredentials() {}
}
