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

    var isConnected: Bool { controller.isConnected }

    var connectionStatePublisher: AnyPublisher<Bool, Never> {
        controller.$isConnected.eraseToAnyPublisher()
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
    
    nonisolated var objectWillChange: ObservableObjectPublisher {
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

    var decoderSoftware: String {
        reporter.decoderSoftware
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
        return QRZUploadResult(success: result.success, errorMessage: result.errorMessage, logID: result.logID)
    }

    func fetchConfirmations(since date: Date) async -> String? {
        let count = await service.fetchConfirmations(since: date)
        return count > 0 ? "\(count)" : nil
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

// MARK: - eQSL Adapter

/// Adapter that wraps FTHamPremium.eQSLService to conform to local eQSLServiceProtocol.
@MainActor
private final class eQSLServiceAdapter: eQSLServiceProtocol {
    private let service: FTHamPremium.eQSLService

    nonisolated let objectWillChange = ObservableObjectPublisher()

    var pendingCount: Int { service.pendingCount }
    var lastError: String? { service.lastError }
    var isSyncing: Bool { service.isSyncing }
    var hasCredentials: Bool { service.hasCredentials }

    private var cancellable: AnyCancellable?

    init(service: FTHamPremium.eQSLService) {
        self.service = service
        cancellable = service.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func uploadADIF(_ adif: String) async -> eQSLUploadResult {
        let result = await service.uploadADIF(adif)
        return eQSLUploadResult(success: result.success, errorMessage: result.errorMessage)
    }

    func fetchConfirmations(since date: Date) async -> String? {
        await service.fetchConfirmations(since: date)
    }

    func saveCredentials(callsign: String, password: String) throws {
        try service.saveCredentials(callsign: callsign, password: password)
    }

    func deleteCredentials() {
        service.deleteCredentials()
    }
}

// MARK: - Band Hop Adapter

/// Adapter that wraps FTHamPremium.BandHopScheduler to conform to local BandHopSchedulerProtocol.
@MainActor
private final class BandHopAdapter: BandHopSchedulerProtocol {
    private let scheduler: FTHamPremium.BandHopScheduler

    init(scheduler: FTHamPremium.BandHopScheduler) {
        self.scheduler = scheduler
    }

    private static func map(_ state: FTHamPremium.BandHopState) -> BandHopState {
        switch state {
        case .stopped: return .stopped
        case .dwelling(let band, let until): return .dwelling(bandRaw: band, until: until)
        case .paused(let band, let remaining): return .paused(bandRaw: band, remaining: remaining)
        }
    }

    var state: BandHopState { Self.map(scheduler.state) }

    var statePublisher: AnyPublisher<BandHopState, Never> {
        scheduler.statePublisher.map(Self.map).eraseToAnyPublisher()
    }

    var hopRequests: AnyPublisher<String, Never> { scheduler.hopRequests }

    func start(schedule: BandHopSchedule, startingAt bandRaw: String?) {
        let steps = schedule.steps.map {
            FTHamPremium.BandHopStep(id: $0.id, bandRaw: $0.bandRaw, dwellMinutes: $0.dwellMinutes)
        }
        scheduler.start(schedule: FTHamPremium.BandHopSchedule(steps: steps), startingAt: bandRaw)
    }

    func stop() { scheduler.stop() }
    func pause() { scheduler.pause() }
    func resume() { scheduler.resume() }
    func skipToNext() { scheduler.skipToNext() }
}

// MARK: - iCloud Logbook Adapter

/// Adapter that wraps FTHamPremium.CloudLogbookSyncService to conform to
/// the local CloudLogbookSyncProtocol.
@MainActor
private final class CloudLogbookSyncAdapter: CloudLogbookSyncProtocol {
    private let service: FTHamPremium.CloudLogbookSyncService

    init(service: FTHamPremium.CloudLogbookSyncService) {
        self.service = service
    }

    func accountStatus() async -> CloudSyncAccountStatus {
        switch await service.accountStatus() {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .unknown: return .unknown
        }
    }

    func push(_ records: [CloudLogRecord]) async throws {
        do {
            try await service.push(records.map(Self.map))
        } catch let error as FTHamPremium.CloudLogbookSyncError {
            throw Self.map(error)
        }
    }

    func pullChanges() async throws -> CloudPullResult {
        do {
            let result = try await service.pullChanges()
            return CloudPullResult(
                upserted: result.upserted.map(Self.map),
                deletedKeys: result.deletedKeys
            )
        } catch let error as FTHamPremium.CloudLogbookSyncError {
            throw Self.map(error)
        }
    }

    func deleteAllRemote() async throws {
        do {
            try await service.deleteAllRemote()
        } catch let error as FTHamPremium.CloudLogbookSyncError {
            throw Self.map(error)
        }
    }

    func resetChangeToken() { service.resetChangeToken() }

    private static func map(_ r: CloudLogRecord) -> FTHamPremium.CloudLogRecord {
        FTHamPremium.CloudLogRecord(
            dedupKey: r.dedupKey, sourceID: r.sourceID, callsign: r.callsign, grid: r.grid,
            date: r.date, frequencyHz: r.frequencyHz, mode: r.mode, band: r.band,
            rstSent: r.rstSent, rstRcvd: r.rstRcvd, stationCallsign: r.stationCallsign,
            cqModifier: r.cqModifier, mySigInfo: r.mySigInfo, country: r.country,
            flag: r.flag, qrzStatusRaw: r.qrzStatusRaw, lotwStatusRaw: r.lotwStatusRaw
        )
    }

    private static func map(_ r: FTHamPremium.CloudLogRecord) -> CloudLogRecord {
        CloudLogRecord(
            dedupKey: r.dedupKey, sourceID: r.sourceID, callsign: r.callsign, grid: r.grid,
            date: r.date, frequencyHz: r.frequencyHz, mode: r.mode, band: r.band,
            rstSent: r.rstSent, rstRcvd: r.rstRcvd, stationCallsign: r.stationCallsign,
            cqModifier: r.cqModifier, mySigInfo: r.mySigInfo, country: r.country,
            flag: r.flag, qrzStatusRaw: r.qrzStatusRaw, lotwStatusRaw: r.lotwStatusRaw
        )
    }

    private static func map(_ error: FTHamPremium.CloudLogbookSyncError) -> CloudLogbookSyncError {
        switch error {
        case .premiumRequired: return .premiumRequired
        case .notAvailable: return .notAvailable
        case .network(let message): return .network(message)
        case .server(let message): return .server(message)
        }
    }
}

// MARK: - Presence Adapter

/// Adapter that wraps FTHamPremium.PresenceService to conform to the local
/// PresenceServiceProtocol.
@MainActor
private final class PresenceAdapter: PresenceServiceProtocol {
    private let service: FTHamPremium.PresenceService

    init(service: FTHamPremium.PresenceService) {
        self.service = service
    }

    func upsert(callsign: String, grid4: String, band: String, mode: String) async throws {
        do {
            try await service.upsert(callsign: callsign, grid4: grid4, band: band, mode: mode)
        } catch let error as FTHamPremium.PresenceError {
            throw Self.map(error)
        }
    }

    func fetchOnline(since date: Date) async throws -> [PresenceStation] {
        do {
            return try await service.fetchOnline(since: date).map {
                PresenceStation(callsign: $0.callsign, grid: $0.grid, band: $0.band, mode: $0.mode, lastSeen: $0.lastSeen)
            }
        } catch let error as FTHamPremium.PresenceError {
            throw Self.map(error)
        }
    }

    func removeMine() async throws {
        do {
            try await service.removeMine()
        } catch let error as FTHamPremium.PresenceError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: FTHamPremium.PresenceError) -> PresenceError {
        switch error {
        case .premiumRequired: return .premiumRequired
        case .notAvailable: return .notAvailable
        case .network(let message): return .network(message)
        }
    }
}

#endif

/// Factory for premium features.
/// Returns real implementations when FTHamPremium package is available,
/// or stub implementations for public-only builds.
/// Each property is backed by a private cache so adapters (and their Combine subscriptions)
/// are created only once per app session.
@MainActor
public enum PremiumFeatures {

    private static var _catController: (any CATControlProtocol)?
    public static var catController: any CATControlProtocol {
        if let existing = _catController { return existing }
        let instance: any CATControlProtocol = {
            #if canImport(FTHamPremium)
            return CATControlAdapter(controller: FTHamPremium.CatRigController.shared)
            #else
            return CATControlStub.shared
            #endif
        }()
        _catController = instance
        return instance
    }

    private static var _pskReporter: (any PSKReporterProtocol)?
    public static var pskReporter: any PSKReporterProtocol {
        if let existing = _pskReporter { return existing }
        let instance: any PSKReporterProtocol = {
            #if canImport(FTHamPremium)
            return PSKReporterAdapter(reporter: FTHamPremium.PSKReporterReporter.shared)
            #else
            return PSKReporterStub.shared
            #endif
        }()
        _pskReporter = instance
        return instance
    }

    private static var _qrzService: (any QRZServiceProtocol)?
    public static var qrzService: any QRZServiceProtocol {
        if let existing = _qrzService { return existing }
        let instance: any QRZServiceProtocol = {
            #if canImport(FTHamPremium)
            return QRZServiceAdapter(service: FTHamPremium.QRZService.shared)
            #else
            return QRZServiceStub.shared
            #endif
        }()
        _qrzService = instance
        return instance
    }

    private static var _lotwService: (any LoTWServiceProtocol)?
    public static var lotwService: any LoTWServiceProtocol {
        if let existing = _lotwService { return existing }
        let instance: any LoTWServiceProtocol = {
            #if canImport(FTHamPremium)
            return LoTWServiceAdapter(service: FTHamPremium.LoTWService.shared)
            #else
            return LoTWServiceStub.shared
            #endif
        }()
        _lotwService = instance
        return instance
    }

    private static var _bandHopScheduler: (any BandHopSchedulerProtocol)?
    public static var bandHopScheduler: any BandHopSchedulerProtocol {
        if let existing = _bandHopScheduler { return existing }
        let instance: any BandHopSchedulerProtocol = {
            #if canImport(FTHamPremium)
            return BandHopAdapter(scheduler: FTHamPremium.BandHopScheduler.shared)
            #else
            return BandHopSchedulerStub.shared
            #endif
        }()
        _bandHopScheduler = instance
        return instance
    }

    private static var _cloudLogbookSync: (any CloudLogbookSyncProtocol)?
    public static var cloudLogbookSync: any CloudLogbookSyncProtocol {
        if let existing = _cloudLogbookSync { return existing }
        let instance: any CloudLogbookSyncProtocol = {
            #if canImport(FTHamPremium)
            return CloudLogbookSyncAdapter(service: FTHamPremium.CloudLogbookSyncService.shared)
            #else
            return CloudLogbookSyncStub.shared
            #endif
        }()
        _cloudLogbookSync = instance
        return instance
    }

    private static var _presence: (any PresenceServiceProtocol)?
    public static var presence: any PresenceServiceProtocol {
        if let existing = _presence { return existing }
        let instance: any PresenceServiceProtocol = {
            #if canImport(FTHamPremium)
            return PresenceAdapter(service: FTHamPremium.PresenceService.shared)
            #else
            return PresenceServiceStub.shared
            #endif
        }()
        _presence = instance
        return instance
    }

    private static var _eqslService: (any eQSLServiceProtocol)?
    public static var eqslService: any eQSLServiceProtocol {
        if let existing = _eqslService { return existing }
        let instance: any eQSLServiceProtocol = {
            #if canImport(FTHamPremium)
            return eQSLServiceAdapter(service: FTHamPremium.eQSLService.shared)
            #else
            return eQSLServiceStub.shared
            #endif
        }()
        _eqslService = instance
        return instance
    }
}
