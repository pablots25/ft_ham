//
//  PSKReporterReporter.swift
//  ft8_ham
//
//  Correct IPFIX implementation compatible with PSK Reporter (WSJT-X model)
//  Public interface unchanged
//

import Foundation
import Network

final class PSKReporterReporter: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = PSKReporterReporter()
    private init() {
        logger.info("PSKReporterReporter initialized")
    }
    
    // MARK: - Logger
    
    private let logger = AppLogger(category: "PSKReporter")
    
    // MARK: - Public API (UNCHANGED)
    
    @Published private(set) var stats = PSKReporterStats()
    @Published var debugLog: [String] = []
    @Published var lastError: String?
    @Published var lastPacket: Data?
    @Published var lastReport: PSKReporterReport?
    @Published var isTestMode: Bool = false
    
    // MARK: - Configuration
    
    private let host = "report.pskreporter.info"
    private let port: UInt16 = 4739
    
    private let enterpriseNumber: UInt32 = 30351
    private let templateID: UInt16 = 256
    private let holdbackInterval: TimeInterval = 300
    private let templateResendInterval = 20
    
    // MARK: - State
    
    private var sequenceNumber: UInt32 = 0
    private var templateCounter = 0
    private var lastSent: [String: Date] = [:]
    private var pendingReports: [String: PSKReporterReport] = [:]
    private let queue = DispatchQueue(label: "PSKReporterReporterQueue")
    
    // MARK: - Entry Point (UNCHANGED)
    
    func report(_ report: PSKReporterReport, testMode: Bool = false) {
        queue.async { [weak self] in
            self?._report(report, testMode: testMode)
        }
    }
    
    func flushPendingReports() {
        queue.async { [weak self] in
            self?._flushPendingReports()
        }
    }
    
    // MARK: - Core Logic
    
    private func _report(_ report: PSKReporterReport, testMode: Bool) {
        
        let key = "\(report.senderCallsign.uppercased())_\(report.band)"
        let now = Date()
        
        if let last = lastSent[key],
           now.timeIntervalSince(last) < holdbackInterval {
            DispatchQueue.main.async { [weak self] in
                self?.stats.heldBack += 1
                self?.pendingReports[key] = report
            }
            logger.debug("PSK Reporter: Held back \(report.senderCallsign) on \(report.band) (will flush on exit)")
            return
        }
        
        lastSent[key] = now
        pendingReports.removeValue(forKey: key)
        
        do {
            let packet = try buildPacket(report)
            DispatchQueue.main.async { [weak self] in
                self?.stats.sent += 1
                self?.lastReport = report
                self?.isTestMode = testMode
                self?.lastPacket = packet
            }
            send(packet)
            DispatchQueue.main.async { [weak self] in
                self?.stats.successful += 1
            }
//            logger.debug("PSK Reporter: Sent \(report.senderCallsign) on \(report.band)")
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = error.localizedDescription
                self?.stats.errors += 1
            }
            logger.error("PSK Reporter: Failed to send: \(error.localizedDescription)")
        }
    }
    
    private func _flushPendingReports() {
        guard !pendingReports.isEmpty else {
            logger.info("PSK Reporter: No pending reports to flush")
            return
        }
        
        logger.info("PSK Reporter: Flushing \(pendingReports.count) pending reports")
        
        for (key, report) in pendingReports {
            lastSent[key] = Date()
            
            do {
                let packet = try buildPacket(report)
                DispatchQueue.main.async { [weak self] in
                    self?.stats.sent += 1
                    self?.lastReport = report
                    self?.lastPacket = packet
                }
                send(packet)
                DispatchQueue.main.async { [weak self] in
                    self?.stats.successful += 1
                }
                logger.debug("PSK Reporter: Flushed \(report.senderCallsign) on \(report.band)")
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.lastError = error.localizedDescription
                    self?.stats.errors += 1
                }
                logger.error("PSK Reporter: Failed to flush: \(error.localizedDescription)")
            }
        }
        
        pendingReports.removeAll()
        logger.info("PSK Reporter: Flush complete")
    }
    
    // MARK: - Packet Builder
    
    private func buildPacket(_ report: PSKReporterReport) throws -> Data {
        
        var packet = Data()
        
        sequenceNumber &+= 1
        templateCounter &+= 1
        
        // IPFIX Header
        packet.append(uint16BE(10))
        let lengthIndex = packet.count
        packet.append(uint16BE(0))
        packet.append(uint32BE(UInt32(Date().timeIntervalSince1970)))
        packet.append(uint32BE(sequenceNumber))
        packet.append(uint32BE(0))
        
        if sequenceNumber == 1 || templateCounter >= templateResendInterval {
            packet.append(buildTemplateSet())
            templateCounter = 0
        }
        
        packet.append(buildDataSet(report))
        
        let totalLength = UInt16(packet.count)
        packet.replaceSubrange(lengthIndex..<lengthIndex+2,
                               with: uint16BE(totalLength))
        
        return packet
    }
    
    // MARK: - Template
    
    private func buildTemplateSet() -> Data {
        
        var data = Data()
        
        data.append(uint16BE(2))
        let lengthIndex = data.count
        data.append(uint16BE(0))
        
        data.append(uint16BE(templateID))
        data.append(uint16BE(9)) // field count
        
        // flowStartSeconds
        data.append(ipfixField(id: 150, length: 4))
        
        // transmitterCallsign
        data.append(ipfixEnterpriseField(id: 1))
        
        // receiverCallsign
        data.append(ipfixEnterpriseField(id: 2))
        
        // receiverLocator
        data.append(ipfixEnterpriseField(id: 3))
        
        // frequency (UInt64)
        data.append(ipfixEnterpriseField(id: 4, length: 8))
        
        // snr (Int16)
        data.append(ipfixEnterpriseField(id: 5, length: 2))
        
        // programName (string)
        data.append(ipfixEnterpriseField(id: 7))
        
        // programVersion (string)
        data.append(ipfixEnterpriseField(id: 8))
        
        // band (string)
        data.append(ipfixEnterpriseField(id: 10))
        
        let totalLength = UInt16(data.count)
        data.replaceSubrange(lengthIndex..<lengthIndex+2,
                             with: uint16BE(totalLength))
        
        return data
    }
    
    // MARK: - Data Set
    
    private func buildDataSet(_ report: PSKReporterReport) -> Data {
        
        var data = Data()
        
        data.append(uint16BE(templateID))
        let lengthIndex = data.count
        data.append(uint16BE(0))
        
        data.append(uint32BE(UInt32(Date().timeIntervalSince1970)))
        
        data.append(variableString(report.senderCallsign))
        data.append(variableString(report.receiverCallsign))
        data.append(variableString(report.receiverLocator))
        
        data.append(uint64BE(report.frequencyHz))
        data.append(int16BE(Int16(report.snr)))
        
        let version = Bundle.main.shortVersion
        data.append(variableString("FT Ham v\(version)"))
        data.append(variableString(version))
        data.append(variableString(report.band))
        
        let totalLength = UInt16(data.count)
        data.replaceSubrange(lengthIndex..<lengthIndex+2,
                             with: uint16BE(totalLength))
        
        return data
    }
    
    // MARK: - UDP
    
    private func send(_ data: Data) {
        let params = NWParameters.udp
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        
        let connection = NWConnection(to: endpoint, using: params)
        connection.start(queue: queue)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // MARK: - Helpers
    
    private func ipfixField(id: UInt16, length: UInt16) -> Data {
        var d = Data()
        d.append(uint16BE(id))
        d.append(uint16BE(length))
        return d
    }
    
    private func ipfixEnterpriseField(id: UInt16, length: UInt16 = 0xFFFF) -> Data {
        var d = Data()
        d.append(uint16BE(0x8000 | id))
        d.append(uint16BE(length))
        d.append(uint32BE(enterpriseNumber))
        return d
    }
    
    private func variableString(_ string: String) -> Data {
        let utf8 = Array(string.utf8)
        var d = Data()
        d.append(UInt8(utf8.count))
        d.append(contentsOf: utf8)
        return d
    }
    
    private func uint16BE(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xff)])
    }
    
    private func uint32BE(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
    
    private func uint64BE(_ value: UInt64) -> Data {
        Data([
            UInt8((value >> 56) & 0xff),
            UInt8((value >> 48) & 0xff),
            UInt8((value >> 40) & 0xff),
            UInt8((value >> 32) & 0xff),
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
    
    private func int16BE(_ value: Int16) -> Data {
        let u = UInt16(bitPattern: value)
        return uint16BE(u)
    }
    
    private func band(from frequency: UInt64) -> String {
        switch frequency {
        case 14000000...14350000: return "20m"
        case 7000000...7300000: return "40m"
        case 21000000...21450000: return "15m"
        default: return "other"
        }
    }
}

// MARK: - Supporting Types

struct PSKReporterStats {
    var sent: Int = 0
    var successful: Int = 0
    var heldBack: Int = 0
    var errors: Int = 0
}

struct PSKReporterReport {
    let receiverCallsign: String
    let senderCallsign: String
    let receiverLocator: String
    let frequencyHz: UInt64
    let mode: PSKReporterMode
    let snr: Int
    let speed: Int
    let band: String
}

enum PSKReporterMode: Int {
    case ft8 = 0
    case ft4 = 1
    // Add more as needed
}
