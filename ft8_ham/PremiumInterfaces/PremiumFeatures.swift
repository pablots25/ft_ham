//
//  PremiumFeatures.swift
//  ft_ham
//
//  Created by Pablo Turrion on 01/03/26.
//
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

    func connect(host: String, port: UInt16) {
        controller.connect(host: host, port: port)
    }

    func disconnect() {
        controller.disconnect()
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

// MARK: - QRZ Adapter

/// Adapter that wraps FTHamPremium.QRZService to conform to local QRZServiceProtocol.
@MainActor
private final class QRZServiceAdapter: QRZServiceProtocol {
    private let service: FTHamPremium.QRZService

    nonisolated let objectWillChange = ObservableObjectPublisher()

    var pendingCount: Int { service.pendingCount }
    var lastError: String? { service.lastError }
    var isSyncing: Bool { service.isSyncing }
    var hasAPIKey: Bool { service.hasAPIKey }

    private var cancellable: AnyCancellable?

    init(service: FTHamPremium.QRZService) {
        self.service = service
        cancellable = service.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func uploadADIF(_ adif: String) async -> QRZUploadResult {
        let result = await service.uploadADIF(adif)
        return QRZUploadResult(success: result.success, errorMessage: result.errorMessage)
    }

    func fetchConfirmations(since date: Date) async -> String? {
        await service.fetchConfirmations(since: date)
    }

    func saveAPIKey(_ key: String) throws {
        try service.saveAPIKey(key)
    }

    func deleteAPIKey() {
        service.deleteAPIKey()
    }
}

// MARK: - LoTW Adapter

/// Adapter that wraps FTHamPremium.LoTWService to conform to local LoTWServiceProtocol.
@MainActor
private final class LoTWServiceAdapter: LoTWServiceProtocol {
    private let service: FTHamPremium.LoTWService

    nonisolated let objectWillChange = ObservableObjectPublisher()

    var pendingCount: Int { service.pendingCount }
    var lastError: String? { service.lastError }
    var isSyncing: Bool { service.isSyncing }
    var hasCertificate: Bool { service.hasCertificate }
    var hasAccountCredentials: Bool { service.hasAccountCredentials }

    private var cancellable: AnyCancellable?

    init(service: FTHamPremium.LoTWService) {
        self.service = service
        cancellable = service.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func uploadADIF(_ adif: String) async -> LoTWUploadResult {
        let result = await service.uploadADIF(adif)
        return LoTWUploadResult(success: result.success, errorMessage: result.errorMessage)
    }

    func fetchConfirmations(since date: Date) async -> String? {
        await service.fetchConfirmations(since: date)
    }

    func importCertificate(from url: URL, password: String) async throws {
        try await service.importCertificate(from: url, password: password)
    }

    func deleteCertificate() {
        service.deleteCertificate()
    }

    func saveAccountCredentials(callsign: String, password: String) throws {
        try service.saveAccountCredentials(callsign: callsign, password: password)
    }

    func deleteAccountCredentials() {
        service.deleteAccountCredentials()
    }
}

#endif

/// Factory for premium features
/// Returns real implementations when FTHamPremium package is available,
/// or stub implementations for public-only builds
@MainActor
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

    /// Get QRZ service instance
    /// Returns real implementation if premium package is linked, stub otherwise
    public static var qrzService: any QRZServiceProtocol {
        #if canImport(FTHamPremium)
        return QRZServiceAdapter(service: FTHamPremium.QRZService.shared)
        #else
        return QRZServiceStub.shared
        #endif
    }

    /// Get LoTW service instance
    /// Returns real implementation if premium package is linked, stub otherwise
    public static var lotwService: any LoTWServiceProtocol {
        #if canImport(FTHamPremium)
        return LoTWServiceAdapter(service: FTHamPremium.LoTWService.shared)
        #else
        return LoTWServiceStub.shared
        #endif
    }
}
