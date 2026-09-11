//
//  SNTPClient.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import Network

/// Anything that can measure the local clock offset against a time server.
protocol SNTPQuerying: Sendable {
    func query(host: String) async throws -> SNTPClient.Sample
}

/// Minimal SNTP (RFC 4330) client over UDP.
actor SNTPClient: SNTPQuerying {

    struct Sample: Equatable, Sendable {
        /// Seconds to add to the local clock to obtain server time.
        let offset: TimeInterval
        let roundTrip: TimeInterval
        let stratum: UInt8
    }

    enum SNTPError: Error, Equatable {
        case timeout
        case shortResponse
        case notAServerReply
        case kissOfDeath
        case network(String)
    }

    /// Seconds between the NTP epoch (1900) and the Unix epoch (1970).
    static let ntpEpochOffset: TimeInterval = 2_208_988_800
    static let packetLength = 48

    private let port: UInt16
    private let timeout: Duration

    init(port: UInt16 = 123, timeout: Duration = .seconds(3)) {
        self.port = port
        self.timeout = timeout
    }

    // MARK: - Query

    func query(host: String) async throws -> Sample {
        let t1 = Date()
        let request = Self.makeRequest(t1: t1)
        let response = try await Self.exchange(request, host: host, port: port, timeout: timeout)
        let t4 = Date()
        return try Self.parse(response, t1: t1, t4: t4)
    }

    // MARK: - Packet building / parsing (pure, testable)

    /// 48-byte client request: LI = 0, VN = 4, Mode = 3 (client), with our
    /// send time in the Transmit Timestamp field so the reply echoes it.
    static func makeRequest(t1: Date) -> Data {
        var packet = Data(count: packetLength)
        packet[0] = 0x23 // 00 100 011
        let (seconds, fraction) = ntpTimestamp(from: t1)
        packet.replaceSubrange(40..<44, with: bytes(seconds))
        packet.replaceSubrange(44..<48, with: bytes(fraction))
        return packet
    }

    /// Offset = ((T2 − T1) + (T3 − T4)) / 2, delay = (T4 − T1) − (T3 − T2).
    static func parse(_ data: Data, t1: Date, t4: Date) throws -> Sample {
        guard data.count >= packetLength else { throw SNTPError.shortResponse }
        let bytes = [UInt8](data.prefix(packetLength))
        let mode = bytes[0] & 0x07
        guard mode == 4 || mode == 5 else { throw SNTPError.notAServerReply }
        let stratum = bytes[1]
        guard stratum != 0 else { throw SNTPError.kissOfDeath }

        let t2 = date(seconds: readUInt32(bytes, at: 32), fraction: readUInt32(bytes, at: 36))
        let t3 = date(seconds: readUInt32(bytes, at: 40), fraction: readUInt32(bytes, at: 44))

        let offset = ((t2.timeIntervalSince(t1)) + (t3.timeIntervalSince(t4))) / 2
        let roundTrip = t4.timeIntervalSince(t1) - t3.timeIntervalSince(t2)
        return Sample(offset: offset, roundTrip: max(0, roundTrip), stratum: stratum)
    }

    static func ntpTimestamp(from date: Date) -> (seconds: UInt32, fraction: UInt32) {
        let ntp = date.timeIntervalSince1970 + ntpEpochOffset
        let seconds = floor(ntp)
        let fraction = (ntp - seconds) * 4_294_967_296.0
        return (UInt32(seconds), UInt32(min(fraction, 4_294_967_295.0)))
    }

    static func date(seconds: UInt32, fraction: UInt32) -> Date {
        let ntp = TimeInterval(seconds) + TimeInterval(fraction) / 4_294_967_296.0
        return Date(timeIntervalSince1970: ntp - ntpEpochOffset)
    }

    private static func bytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func readUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16
            | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
    }

    // MARK: - Transport

    /// One UDP request/response with a timeout. The continuation is guarded
    /// so late callbacks from the connection cannot resume it twice.
    private static func exchange(_ request: Data, host: String, port: UInt16, timeout: Duration) async throws -> Data {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SNTPError.network("invalid port \(port)")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        let gate = ResumeGate()

        let receive: Task<Data, Error> = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: request, completion: .contentProcessed { error in
                            if let error {
                                gate.resume { continuation.resume(throwing: SNTPError.network(error.localizedDescription)) }
                                return
                            }
                            connection.receiveMessage { data, _, _, error in
                                if let error {
                                    gate.resume { continuation.resume(throwing: SNTPError.network(error.localizedDescription)) }
                                } else if let data {
                                    gate.resume { continuation.resume(returning: data) }
                                } else {
                                    gate.resume { continuation.resume(throwing: SNTPError.shortResponse) }
                                }
                            }
                        })
                    case .failed(let error):
                        gate.resume { continuation.resume(throwing: SNTPError.network(error.localizedDescription)) }
                    case .cancelled:
                        gate.resume { continuation.resume(throwing: SNTPError.timeout) }
                    default:
                        break
                    }
                }
                connection.start(queue: DispatchQueue(label: "sntp.\(host)"))
            }
        }

        let timer = Task {
            try await Task.sleep(for: timeout)
            connection.cancel()
        }
        defer {
            timer.cancel()
            connection.cancel()
        }

        return try await receive.value
    }

    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func resume(_ body: () -> Void) {
            lock.lock()
            let first = !resumed
            resumed = true
            lock.unlock()
            if first { body() }
        }
    }
}
