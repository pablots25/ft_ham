//
//  eQSLServiceStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/04/26.
//

import Foundation
import Combine

/// No-op eQSL service used when premium package is not available.
@MainActor
public final class eQSLServiceStub: eQSLServiceProtocol {
    public static let shared = eQSLServiceStub()
    public nonisolated let objectWillChange = ObservableObjectPublisher()

    public var pendingCount: Int { 0 }
    public var lastError: String? { nil }
    public var isSyncing: Bool { false }
    public var hasCredentials: Bool { false }

    private init() {}

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
