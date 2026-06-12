//
//  QRZServiceStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import Foundation
import Combine

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
