//
//  CATProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 01/03/26.
//
//

import Foundation

// MARK: - Data Structures

public struct CatRigResponse {
    public let success: Bool
    public let response: String
    public let errorMessage: String?
    
    public init(success: Bool, response: String, errorMessage: String? = nil) {
        self.success = success
        self.response = response
        self.errorMessage = errorMessage
    }
}

public enum CatRigError: LocalizedError {
    case invalidPort
    case timeout
    case connectionFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case invalidResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Invalid TCP port"
        case .timeout:
            return "CAT request timed out"
        case .connectionFailed(let message):
            return "CAT connection failed: \(message)"
        case .sendFailed(let message):
            return "CAT send failed: \(message)"
        case .receiveFailed(let message):
            return "CAT receive failed: \(message)"
        case .invalidResponse:
            return "CAT response was empty"
        case .cancelled:
            return "CAT command was cancelled"
        }
    }
}

// MARK: - Protocol

/// Public protocol for CAT control
/// Premium implementation provides real rigctld integration
/// Stub implementation provides NO-OP methods for public-only builds
public protocol CATControlProtocol: Sendable {
    /// Open a persistent connection to rigctld
    func connect(host: String, port: UInt16)

    /// Close the persistent connection
    func disconnect()

    /// Set PTT (Push To Talk) state
    func setPTT(enabled: Bool, host: String, port: UInt16) async -> CatRigResponse
    
    /// Set transceiver frequency
    func setFrequency(frequency: Int64, host: String, port: UInt16) async -> CatRigResponse
    
    /// Get current transceiver frequency
    func getFrequency(host: String, port: UInt16) async -> CatRigResponse
}
