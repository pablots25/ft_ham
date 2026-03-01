//
//  PSKReporterReporter.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 27/02/26.


//  RFC 7011 compliant IPFIX implementation for PSK Reporter
//  Based on official PSK Reporter specification: https://pskreporter.info/pskdev.html
//  Enterprise Number: 30351 (PSK Reporter)
//
//  OFFICIAL Field IDs (30351.x):
//  1: senderCallsign (transmitterCallsign)
//  2: receiverCallsign
//  4: receiverLocator (Maidenhead grid locator)
//  5: frequency (Hz, UInt32 - 4 bytes)
//  6: sNR (dB, Int8 - 1 byte, -128 to +127)
//  8: decoderSoftware (program name and version)
//  10: mode (string, e.g., "FT8", "FT4")
//  11: informationSource (UInt8 - 1 byte, 1=automatic, 2=QSO, 0x80=test)
//
//  Template IDs:
//  0x9992 (39314): Receiver information template
//  0x9993 (39315): Sender information template

import Foundation
import Network

final class PSKReporterReporter: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = PSKReporterReporter()
    private init() {
        logger.info("PSKReporterReporter initialized (RFC 7011 + Official Spec)")
    }
    
    // MARK: - Logger
    
    private let logger = AppLogger(category: "PSKReporter")
    
    // MARK: - Public API
    
    @Published private(set) var stats = PSKReporterStats()
    @Published var debugLog: [String] = []
    @Published var lastError: String?
    @Published var lastPacket: Data?
    @Published var lastReport: PSKReporterReport?
    @Published var isTestMode: Bool = false
    
    // MARK: - Configuration
    
    private let host = "report.pskreporter.info"
    private let port: UInt16 = 4739
    
    // IANA Enterprise Number for PSK Reporter
    private let enterpriseNumber: UInt32 = 30351
    
    // Template IDs (as per official spec)
    private let receiverTemplateID: UInt16 = 0x9992  // 39314
    private let senderTemplateID: UInt16 = 0x9993    // 39315
    
    // Reporting settings
    private let holdbackInterval: TimeInterval = 300      // 5 minutes
    private let templateResendInterval = 3                // First 3 packets, then hourly
    
    private let reporterProgramName = "FT Ham"
    
    // MARK: - State
    
    private var sequenceNumber: UInt32 = 0
    private var packetsSinceTemplate = 0
    private var lastSent: [String: Date] = [:]
    private var pendingReports: [String: PSKReporterReport] = [:]
    private let queue = DispatchQueue(label: "PSKReporterReporterQueue")
    private var sessionIdentifier: UInt32 = 0
    
    // MARK: - Entry Point
    
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
        
        if sessionIdentifier == 0 {
            sessionIdentifier = UInt32.random(in: 1...0xFFFFFFFF)
        }
        
        let key = "\(report.senderCallsign.uppercased())_\(report.frequencyHz)"
        let now = Date()
        
        if let last = lastSent[key],
           now.timeIntervalSince(last) < holdbackInterval {
            DispatchQueue.main.async { [weak self] in
                self?.stats.heldBack += 1
                self?.pendingReports[key] = report
            }
            return
        }
        
        lastSent[key] = now
        pendingReports.removeValue(forKey: key)
        
        do {
            let packet = try buildPacket(report, testMode: testMode)
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
            packetsSinceTemplate += 1
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = error.localizedDescription
                self?.stats.errors += 1
            }
            logger.error("PSK Reporter send failed: \(error.localizedDescription)")
        }
    }
    
    private func _flushPendingReports() {
        guard !pendingReports.isEmpty else { return }
        
        for (key, report) in pendingReports {
            lastSent[key] = Date()
            
            do {
                let packet = try buildPacket(report, testMode: false)
                DispatchQueue.main.async { [weak self] in
                    self?.stats.sent += 1
                    self?.lastReport = report
                    self?.lastPacket = packet
                }
                send(packet)
                DispatchQueue.main.async { [weak self] in
                    self?.stats.successful += 1
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.lastError = error.localizedDescription
                    self?.stats.errors += 1
                }
            }
        }
        
        pendingReports.removeAll()
    }
    
    // MARK: - Packet Builder (Official Spec)
    
    private func buildPacket(_ report: PSKReporterReport, testMode: Bool) throws -> Data {
        
        var packet = Data()
        
        sequenceNumber &+= 1
        
        // IPFIX Message Header
        packet.append(uint16BE(10))                                    // Version 10
        let lengthIndex = packet.count
        packet.append(uint16BE(0))                                     // Length (calculated below)
        packet.append(uint32BE(UInt32(Date().timeIntervalSince1970))) // Export Time
        packet.append(uint32BE(sequenceNumber))                        // Sequence Number
        packet.append(uint32BE(sessionIdentifier))                     // Observation Domain ID
        
        // Send templates in first 3 packets or every hour (3600 packets at 5 min intervals)
        let needsTemplate = packetsSinceTemplate < templateResendInterval || packetsSinceTemplate >= 720
        
        if needsTemplate {
            packet.append(buildReceiverTemplateSet())
            packet.append(buildSenderTemplateSet())
            packetsSinceTemplate = 0
        }
        
        // Receiver Information Record (ONE per packet)
        packet.append(buildReceiverDataSet(report))
        
        // Sender Information Records (can be multiple, we send one)
        packet.append(buildSenderDataSet(report, testMode: testMode))
        
        // Update total length
        let totalLength = UInt16(packet.count)
        packet.replaceSubrange(lengthIndex..<lengthIndex+2,
                               with: uint16BE(totalLength))
        
        return packet
    }
    
    // MARK: - Template Sets (Official Spec)
    
    // Receiver Information Template (0x9992)
    private func buildReceiverTemplateSet() -> Data {
        
        var data = Data()
        
        // Set Header
        data.append(uint16BE(2))      // Set ID 2 = Template Set
        let lengthIndex = data.count
        data.append(uint16BE(0))      // Set Length (calculated below)
        
        // Template Record Header
        data.append(uint16BE(receiverTemplateID))  // 0x9992
        data.append(uint16BE(3))                   // 3 fields
        
        // Field Specifiers (Enterprise Number 30351)
        data.append(ipfixEnterpriseField(id: 2))   // receiverCallsign (variable)
        data.append(ipfixEnterpriseField(id: 4))   // receiverLocator (variable)
        data.append(ipfixEnterpriseField(id: 8))   // decoderSoftware (variable)
        
        // RFC 7011 Compliance: Padding to 4-byte boundary
        padToMultipleOf4(&data)
        
        let totalLength = UInt16(data.count)
        data.replaceSubrange(lengthIndex..<lengthIndex+2,
                             with: uint16BE(totalLength))
        
        return data
    }
    
    // Sender Information Template (0x9993)
    private func buildSenderTemplateSet() -> Data {
        
        var data = Data()
        
        // Set Header
        data.append(uint16BE(2))      // Set ID 2 = Template Set
        let lengthIndex = data.count
        data.append(uint16BE(0))      // Set Length (calculated below)
        
        // Template Record Header
        data.append(uint16BE(senderTemplateID))    // 0x9993
        data.append(uint16BE(6))                   // 6 fields
        
        // Field Specifiers (Enterprise Number 30351 + Standard Field 150)
        data.append(ipfixEnterpriseField(id: 1))         // senderCallsign (variable)
        data.append(ipfixEnterpriseField(id: 5, length: 4))  // frequency (UInt32, 4 bytes)
        data.append(ipfixEnterpriseField(id: 6, length: 1))  // sNR (Int8, 1 byte)
        data.append(ipfixEnterpriseField(id: 10))        // mode (variable)
        data.append(ipfixEnterpriseField(id: 11, length: 1))  // informationSource (1 byte)
        data.append(ipfixField(id: 150, length: 4))      // flowStartSeconds (UInt32, 4 bytes)
        
        // RFC 7011 Compliance: Padding to 4-byte boundary
        padToMultipleOf4(&data)
        
        let totalLength = UInt16(data.count)
        data.replaceSubrange(lengthIndex..<lengthIndex+2,
                             with: uint16BE(totalLength))
        
        return data
    }
    
    // MARK: - Data Sets (Official Spec)
    
    // Receiver Information Data Set (ONE per packet)
    private func buildReceiverDataSet(_ report: PSKReporterReport) -> Data {
        
        var data = Data()
        
        // Data Set Header
        data.append(uint16BE(receiverTemplateID))  // 0x9992
        let lengthIndex = data.count
        data.append(uint16BE(0))                   // Set Length (calculated below)
        
        // Field 2: receiverCallsign (variable length string)
        data.append(variableString(report.receiverCallsign))
        
        // Field 4: receiverLocator (variable length string)
        data.append(variableString(report.receiverLocator))
        
        // Field 8: decoderSoftware (combined program name and version)
        let version = Bundle.main.shortVersion
        let decoderSoftware = "\(reporterProgramName) - \(version)"
        data.append(variableString(decoderSoftware))
        
        // RFC 7011 Compliance: Padding to 4-byte boundary
        padToMultipleOf4(&data)
        
        let totalLength = UInt16(data.count)
        data.replaceSubrange(lengthIndex..<lengthIndex+2,
                             with: uint16BE(totalLength))
        
        return data
    }
    
    // Sender Information Data Set (can be multiple, we send one)
    private func buildSenderDataSet(_ report: PSKReporterReport, testMode: Bool) -> Data {
        
        var data = Data()
        
        // Data Set Header
        data.append(uint16BE(senderTemplateID))    // 0x9993
        let lengthIndex = data.count
        data.append(uint16BE(0))                   // Set Length (calculated below)
        
        // Field 1: senderCallsign (variable length string)
        data.append(variableString(report.senderCallsign))
        
        // Field 5: frequency (UInt32, 4 bytes, Hz)
        // Convert UInt64 to UInt32 (truncate upper 32 bits)
        let frequency32 = UInt32(truncatingIfNeeded: report.frequencyHz)
        data.append(uint32BE(frequency32))
        
        // Field 6: sNR (Int8, 1 byte, dB)
        // Clamp SNR to Int8 range (-128 to 127)
        let snr8 = Int8(clamping: report.snr)
        data.append(int8(snr8))
        
        // Field 10: mode (variable length string)
        data.append(variableString(modeString(from: report.mode)))
        
        // Field 11: informationSource (1 byte)
        // 0x01 = automatic, 0x81 = test mode
        data.append(testMode ? 0x81 : 0x01)
        
        // Field 150: flowStartSeconds (UInt32, 4 bytes, seconds since 1970)
        data.append(uint32BE(UInt32(Date().timeIntervalSince1970)))
        
        // RFC 7011 Compliance: Padding to 4-byte boundary
        padToMultipleOf4(&data)
        
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
    
    private func padToMultipleOf4(_ data: inout Data) {
        let remainder = data.count % 4
        if remainder != 0 {
            let paddingNeeded = 4 - remainder
            data.append(contentsOf: Array(repeating: UInt8(0), count: paddingNeeded))
        }
    }
    
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
    
    private func int8(_ value: Int8) -> Data {
        Data([UInt8(bitPattern: value)])
    }
    
    private func modeString(from mode: PSKReporterMode) -> String {
        // Mode strings must match PSK Reporter conventions
        switch mode {
        case .ft8: return "FT8"
        case .ft4: return "FT4"
        }
    }
}

// MARK: - Extensions

extension Int8 {
    /// Initialize Int8 with clamping from any BinaryInteger type.
    /// Values outside -128...127 are clamped to those bounds.
    init<T: BinaryInteger>(clamping value: T) {
        if value < Int8.min {
            self = Int8.min
        } else if value > Int8.max {
            self = Int8.max
        } else {
            self = Int8(value)
        }
    }
}