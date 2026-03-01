//
//  PSKReporterProtocol.swift
//  ft8_ham
//
//  Public interface for PSK Reporter integration
//  Premium implementation is in private ft_ham_premium package
//
//  Created on 01/03/26.
//

import Foundation
import Combine

// MARK: - Data Structures

public struct PSKReporterStats {
    public var sent: Int
    public var successful: Int
    public var heldBack: Int
    public var errors: Int
    
    public var totalReports: Int { sent }
    public var successfulReports: Int { successful }
    public var failedReports: Int { errors }
    public var pendingReports: Int { heldBack }
    
    public init(sent: Int = 0, successful: Int = 0, heldBack: Int = 0, errors: Int = 0) {
        self.sent = sent
        self.successful = successful
        self.heldBack = heldBack
        self.errors = errors
    }
}

public struct PSKReporterReport: Sendable {
    public let receiverCallsign: String
    public let senderCallsign: String
    public let receiverLocator: String
    public let frequencyHz: UInt64
    public let mode: PSKReporterMode
    public let snr: Int
    
    public init(
        receiverCallsign: String,
        senderCallsign: String,
        receiverLocator: String,
        frequencyHz: UInt64,
        mode: PSKReporterMode,
        snr: Int
    ) {
        self.receiverCallsign = receiverCallsign
        self.senderCallsign = senderCallsign
        self.receiverLocator = receiverLocator
        self.frequencyHz = frequencyHz
        self.mode = mode
        self.snr = snr
    }
}

public enum PSKReporterMode: Int, Sendable {
    case ft8 = 0
    case ft4 = 1
}

// MARK: - Protocol

/// Public protocol for PSK Reporter integration
/// Premium implementation provides real reporting to pskreporter.info
/// Stub implementation provides NO-OP methods for public-only builds
public protocol PSKReporterProtocol: ObservableObject, Sendable {
    /// Current statistics
    var stats: PSKReporterStats { get }
    
    /// Debug log entries
    var debugLog: [String] { get }
    
    /// Last error message
    var lastError: String? { get }
    
    /// Last sent packet data
    var lastPacket: Data? { get }
    
    /// Last report that was sent
    var lastReport: PSKReporterReport? { get }
    
    /// Whether test mode is enabled
    var isTestMode: Bool { get }
    
    /// Report a contact to PSK Reporter
    func report(_ report: PSKReporterReport, testMode: Bool)
    
    /// Flush any pending reports
    func flushPendingReports()
}
