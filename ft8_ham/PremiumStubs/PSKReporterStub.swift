//
//  PSKReporterStub.swift
//  ft8_ham
//
//  NO-OP stub implementation for public-only builds
//  Premium implementation is in private ft_ham_premium package
//
//  Created on 01/03/26.
//

import Foundation
import Combine

/// Stub PSK Reporter that does nothing
/// Used when premium package is not available
public final class PSKReporterStub: PSKReporterProtocol {
    public static let shared = PSKReporterStub()
    
    @Published public private(set) var stats = PSKReporterStats()
    @Published public var debugLog: [String] = []
    @Published public var lastError: String?
    @Published public var lastPacket: Data?
    @Published public var lastReport: PSKReporterReport?
    @Published public var isTestMode: Bool = false
    
    private init() {}
    
    public func report(_ report: PSKReporterReport, testMode: Bool = false) {
        // NO-OP - premium feature not available
    }
    
    public func flushPendingReports() {
        // NO-OP - premium feature not available
    }
}
