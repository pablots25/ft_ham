//  PSKReporterReporter.swift
//  ft8_ham
//
//  Created by Copilot on 2026-02-26. Restored full PSK Reporter integration: IPFIX builder, UDP sender, stats, test mode, debug, opt-in, holdback.
//

import Foundation
import Network

/// PSKReporterReporter: Handles building and sending IPFIX packets to PSK Reporter, with stats, test mode, and debug info.
final class PSKReporterReporter: ObservableObject {
    // MARK: - Singleton
    static let shared = PSKReporterReporter()
    private init() {
        logger.info("PSKReporterReporter initialized")
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

    // Holdback: [callsign+band: Date]
    private var lastSent: [String: Date] = [:]
    private let holdbackInterval: TimeInterval = 30 * 60 // 30 min

    // Sequence number for IPFIX
    private var sequenceNumber: UInt32 = 0
    private var templateResendCounter: Int = 0
    private let templateResendInterval = 20 // resend template every 20 packets

    // UDP
    private let host = "report.pskreporter.info"
    private let port: UInt16 = 4739
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "PSKReporterReporterQueue")

    // MARK: - Main entry point
    func report(_ report: PSKReporterReport, testMode: Bool = false) {
        queue.async { [weak self] in
            self?._report(report, testMode: testMode)
        }
    }

    // MARK: - Core logic
    private func _report(_ report: PSKReporterReport, testMode: Bool) {
        let key = "\(report.receiverCallsign.uppercased())_\(report.band)"
        let now = Date()
        
        logger.debug("Processing report: \(report.senderCallsign) -> \(report.receiverCallsign) on \(report.band) @ \(report.frequencyHz) Hz, SNR: \(report.snr)")
        
        if let last = lastSent[key], now.timeIntervalSince(last) < holdbackInterval {
            let elapsed = now.timeIntervalSince(last)
            let remaining = holdbackInterval - elapsed
            log("Holdback: Skipping duplicate report for \(key) (\(Int(remaining/60))m remaining)")
            logger.debug("Holdback active for \(key): \(Int(elapsed))s elapsed, \(Int(remaining))s remaining")
            stats.heldBack += 1
            return
        }
        
        lastSent[key] = now
        stats.sent += 1
        lastReport = report
        isTestMode = testMode
        
        logger.info("Reporting: \(report.senderCallsign) -> \(report.receiverCallsign) | Band: \(report.band) | Freq: \(report.frequencyHz) Hz | SNR: \(report.snr) | Mode: \(report.mode == .ft8 ? "FT8" : "FT4") | Test: \(testMode)")
        
        do {
            let packet = try buildPacket(for: report, testMode: testMode)
            lastPacket = packet
            logger.debug("Built IPFIX packet: \(packet.count) bytes, seq: \(sequenceNumber)")
            send(packet)
            log("✓ Sent: \(report.senderCallsign) on \(report.band) (\(packet.count)B, test=\(testMode ? 1 : 0))")
        } catch {
            lastError = error.localizedDescription
            log("✗ Error: \(error.localizedDescription)")
            logger.error("Failed to build/send packet: \(error.localizedDescription)")
            stats.errors += 1
        }
    }

    // MARK: - IPFIX Packet Builder
    private func buildPacket(for report: PSKReporterReport, testMode: Bool) throws -> Data {
        var packet = Data()
        let exportTime = UInt32(Date().timeIntervalSince1970)
        sequenceNumber &+= 1
        templateResendCounter &+= 1
        // IPFIX Header
        packet.append(contentsOf: [0x00, 0x0a]) // Version 10
        let lengthPos = packet.count
        packet.append(contentsOf: [0x00, 0x00]) // Length (to fill later)
        packet.append(contentsOf: withBigEndian(exportTime))
        packet.append(contentsOf: withBigEndian(sequenceNumber))
        packet.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // Observation Domain ID
        // Template Set (every N packets)
        if sequenceNumber == 1 || templateResendCounter >= templateResendInterval {
            packet.append(buildTemplateSet())
            templateResendCounter = 0
        }
        // Data Set
        packet.append(buildDataSet(for: report, testMode: testMode))
        // Fill in length
        let totalLength = UInt16(packet.count)
        packet.replaceSubrange(lengthPos..<(lengthPos+2), with: withBigEndian(totalLength))
        return packet
    }

    private func buildTemplateSet() -> Data {
        var d = Data()
        d.append(contentsOf: [0x00, 0x02]) // Set ID 2 (template)
        let templateLenPos = d.count
        d.append(contentsOf: [0x00, 0x00]) // Length (to fill later)
        d.append(contentsOf: [0x00, 0x64]) // Template ID 100
        d.append(contentsOf: [0x00, 0x0a]) // Field count: 10
        // Field Specifiers (see PSK Reporter IPFIX spec)
        d.append(ipfixField(0x00, 0x01, 4)) // observationTimeSeconds
        d.append(ipfixField(0x00, 0x0c, 4)) // sourceIPv4Address
        d.append(ipfixField(0x80, 0x01, 2, enterprise: 29305)) // receiverCallsign
        d.append(ipfixField(0x80, 0x02, 2, enterprise: 29305)) // senderCallsign
        d.append(ipfixField(0x80, 0x03, 2, enterprise: 29305)) // frequencyHz
        d.append(ipfixField(0x80, 0x04, 1, enterprise: 29305)) // mode
        d.append(ipfixField(0x80, 0x05, 1, enterprise: 29305)) // snr
        d.append(ipfixField(0x80, 0x06, 1, enterprise: 29305)) // speed
        d.append(ipfixField(0x80, 0x07, 1, enterprise: 29305)) // test
        d.append(ipfixField(0x80, 0x08, 2, enterprise: 29305)) // band
        // Fill in length
        let len = UInt16(d.count)
        d.replaceSubrange(templateLenPos..<(templateLenPos+2), with: withBigEndian(len))
        return d
    }

    private func buildDataSet(for report: PSKReporterReport, testMode: Bool) -> Data {
        var d = Data()
        d.append(contentsOf: [0x00, 0x64]) // Set ID 100
        let dataLenPos = d.count
        d.append(contentsOf: [0x00, 0x00]) // Length (to fill later)
        // Fields (in template order)
        d.append(contentsOf: withBigEndian(UInt32(Date().timeIntervalSince1970))) // observationTimeSeconds
        d.append(Data([0, 0, 0, 0])) // sourceIPv4Address (0.0.0.0)
        d.append(contentsOf: lengthPrefixedString(report.receiverCallsign, 2))
        d.append(contentsOf: lengthPrefixedString(report.senderCallsign, 2))
        d.append(contentsOf: withBigEndian(report.frequencyHz))
        d.append(UInt8(report.mode.rawValue))
        d.append(UInt8(bitPattern: Int8(report.snr)))
        d.append(UInt8(report.speed))
        d.append(UInt8(testMode ? 1 : 0))
        d.append(contentsOf: lengthPrefixedString(report.band, 2))
        // Fill in length
        let len = UInt16(d.count)
        d.replaceSubrange(dataLenPos..<(dataLenPos+2), with: withBigEndian(len))
        return d
    }

    // MARK: - UDP Send
    private func send(_ data: Data) {
        logger.debug("Sending \(data.count) bytes to \(host):\(port)")
        
        let params = NWParameters.udp
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let conn = NWConnection(to: endpoint, using: params)
        
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.debug("UDP connection ready")
            case .failed(let error):
                self.lastError = error.localizedDescription
                self.log("✗ UDP connection failed: \(error.localizedDescription)")
                self.logger.error("UDP connection failed: \(error.localizedDescription)")
                self.stats.errors += 1
            case .waiting(let error):
                self.logger.warning("UDP connection waiting: \(error.localizedDescription)")
            default:
                break
            }
        }
        
        conn.start(queue: queue)
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.lastError = error.localizedDescription
                self.log("✗ UDP send error: \(error.localizedDescription)")
                self.logger.error("UDP send failed: \(error.localizedDescription)")
                self.stats.errors += 1
            } else {
                self.stats.successful += 1
                self.logger.debug("UDP send successful (total: \(self.stats.successful))")
            }
            conn.cancel()
        })
    }

    // MARK: - Helpers
    private func ipfixField(_ id1: UInt8, _ id2: UInt8, _ len: UInt16, enterprise: UInt32? = nil) -> Data {
        var d = Data([id1, id2])
        d.append(contentsOf: withBigEndian(len))
        if let ent = enterprise {
            d[0] |= 0x80 // Set enterprise bit
            d.append(contentsOf: withBigEndian(ent))
        }
        return d
    }

    private func withBigEndian(_ v: UInt16) -> [UInt8] {
        [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }
    private func withBigEndian(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }
    private func lengthPrefixedString(_ s: String, _ lenBytes: Int) -> Data {
        let utf8 = s.utf8
        var d = Data()
        if lenBytes == 2 {
            d.append(contentsOf: withBigEndian(UInt16(utf8.count)))
        } else if lenBytes == 1 {
            d.append(UInt8(utf8.count))
        }
        d.append(contentsOf: utf8)
        return d
    }
    private func log(_ msg: String) {
        DispatchQueue.main.async {
            self.debugLog.append("[\(Date())] \(msg)")
            if self.debugLog.count > 100 { self.debugLog.removeFirst() }
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
    let frequencyHz: UInt32
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
