//
//  PremiumFeatures.swift
//  ft8_ham
//
//  Factory for premium features - provides real or stub implementations
//  based on whether the premium package is available
//
//  Created on 01/03/26.
//

import Foundation
import Combine

#if canImport(FTHamPremium)
import FTHamPremium

// MARK: - Adapters for Premium Features

/// Adapter that wraps FTHamPremium.CatRigController to conform to local CATControlProtocol
private final class CATControlAdapter: CATControlProtocol {
    private let controller: FTHamPremium.CatRigController
    
    init(controller: FTHamPremium.CatRigController) {
        self.controller = controller
    }
    
    func setPTT(enabled: Bool, host: String, port: UInt16) async -> CatRigResponse {
        let result = await controller.setPTT(enabled: enabled, host: host, port: port)
        return CatRigResponse(
            success: result.success,
            response: result.response,
            errorMessage: result.errorMessage
        )
    }
    
    func setFrequency(frequency: Int64, host: String, port: UInt16) async -> CatRigResponse {
        let result = await controller.setFrequency(frequency: frequency, host: host, port: port)
        return CatRigResponse(
            success: result.success,
            response: result.response,
            errorMessage: result.errorMessage
        )
    }
    
    func getFrequency(host: String, port: UInt16) async -> CatRigResponse {
        let result = await controller.getFrequency(host: host, port: port)
        return CatRigResponse(
            success: result.success,
            response: result.response,
            errorMessage: result.errorMessage
        )
    }
}

/// Adapter that wraps FTHamPremium.PSKReporterReporter to conform to local PSKReporterProtocol
private final class PSKReporterAdapter: PSKReporterProtocol {
    private let reporter: FTHamPremium.PSKReporterReporter
    
    var objectWillChange: ObservableObjectPublisher {
        reporter.objectWillChange
    }
    
    var stats: PSKReporterStats {
        let premiumStats = reporter.stats
        return PSKReporterStats(
            sent: premiumStats.sent,
            successful: premiumStats.successful,
            heldBack: premiumStats.heldBack,
            errors: premiumStats.errors
        )
    }
    
    var debugLog: [String] {
        reporter.debugLog
    }
    
    var lastError: String? {
        reporter.lastError
    }
    
    var lastPacket: Data? {
        reporter.lastPacket
    }
    
    var lastReport: PSKReporterReport? {
        guard let premiumReport = reporter.lastReport else { return nil }
        return PSKReporterReport(
            receiverCallsign: premiumReport.receiverCallsign,
            senderCallsign: premiumReport.senderCallsign,
            receiverLocator: premiumReport.receiverLocator,
            frequencyHz: premiumReport.frequencyHz,
            mode: premiumReport.mode.rawValue == 0 ? .ft8 : .ft4,
            snr: premiumReport.snr
        )
    }
    
    var isTestMode: Bool {
        reporter.isTestMode
    }
    
    init(reporter: FTHamPremium.PSKReporterReporter) {
        self.reporter = reporter
    }
    
    func report(_ report: PSKReporterReport, testMode: Bool) {
        let premiumMode: FTHamPremium.PSKReporterMode = report.mode == .ft8 ? .ft8 : .ft4
        let premiumReport = FTHamPremium.PSKReporterReport(
            receiverCallsign: report.receiverCallsign,
            senderCallsign: report.senderCallsign,
            receiverLocator: report.receiverLocator,
            frequencyHz: report.frequencyHz,
            mode: premiumMode,
            snr: report.snr
        )
        reporter.report(premiumReport, testMode: testMode)
    }
    
    func flushPendingReports() {
        reporter.flushPendingReports()
    }
}

#endif

/// Factory for premium features
/// Returns real implementations when FTHamPremium package is available,
/// or stub implementations for public-only builds
public enum PremiumFeatures {
    
    /// Get CAT controller instance
    /// Returns real implementation if premium package is linked, stub otherwise
    public static var catController: any CATControlProtocol {
        #if canImport(FTHamPremium)
        // Premium package available - use adapter for real implementation
        return CATControlAdapter(controller: FTHamPremium.CatRigController.shared)
        #else
        // Premium package not available - use stub
        return CATControlStub.shared
        #endif
    }
    
    /// Get PSK Reporter instance
    /// Returns real implementation if premium package is linked, stub otherwise
    public static var pskReporter: any PSKReporterProtocol {
        #if canImport(FTHamPremium)
        // Premium package available - use adapter for real implementation
        return PSKReporterAdapter(reporter: FTHamPremium.PSKReporterReporter.shared)
        #else
        // Premium package not available - use stub
        return PSKReporterStub.shared
        #endif
    }
}
