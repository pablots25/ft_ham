//
//  SNTPClientTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

final class SNTPClientTests: XCTestCase {

    /// Builds a 48-byte mode-4 server reply with the given receive/transmit times.
    private func reply(t2: Date, t3: Date, mode: UInt8 = 4, stratum: UInt8 = 2) -> Data {
        var packet = Data(count: SNTPClient.packetLength)
        packet[0] = 0x20 | mode // LI 0, VN 4
        packet[1] = stratum
        let (s2, f2) = SNTPClient.ntpTimestamp(from: t2)
        let (s3, f3) = SNTPClient.ntpTimestamp(from: t3)
        for (offset, value) in [(32, s2), (36, f2), (40, s3), (44, f3)] {
            packet[offset] = UInt8(value >> 24)
            packet[offset + 1] = UInt8((value >> 16) & 0xFF)
            packet[offset + 2] = UInt8((value >> 8) & 0xFF)
            packet[offset + 3] = UInt8(value & 0xFF)
        }
        return packet
    }

    func test_makeRequest_isClientModeVersion4With48Bytes() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000.25)
        let request = SNTPClient.makeRequest(t1: t1)
        XCTAssertEqual(request.count, 48)
        XCTAssertEqual(request[0], 0x23)
        // Transmit timestamp echoes t1.
        let bytes = [UInt8](request)
        let seconds = UInt32(bytes[40]) << 24 | UInt32(bytes[41]) << 16 | UInt32(bytes[42]) << 8 | UInt32(bytes[43])
        XCTAssertEqual(TimeInterval(seconds), floor(t1.timeIntervalSince1970 + SNTPClient.ntpEpochOffset))
    }

    func test_ntpTimestamp_roundTrips() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
        let (s, f) = SNTPClient.ntpTimestamp(from: date)
        let back = SNTPClient.date(seconds: s, fraction: f)
        XCTAssertEqual(back.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1e-6)
    }

    func test_parse_computesOffsetAndRoundTrip() throws {
        // Local clock is 2.5 s behind the server; 100 ms network each way;
        // server takes 20 ms to answer.
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let serverT2 = t1.addingTimeInterval(0.1 + 2.5)
        let serverT3 = serverT2.addingTimeInterval(0.02)
        let t4 = t1.addingTimeInterval(0.1 + 0.02 + 0.1)

        let sample = try SNTPClient.parse(reply(t2: serverT2, t3: serverT3), t1: t1, t4: t4)
        XCTAssertEqual(sample.offset, 2.5, accuracy: 1e-4)
        XCTAssertEqual(sample.roundTrip, 0.2, accuracy: 1e-4)
        XCTAssertEqual(sample.stratum, 2)
    }

    func test_parse_negativeOffsetWhenLocalClockIsAhead() throws {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let serverT2 = t1.addingTimeInterval(0.05 - 1.0)
        let serverT3 = serverT2.addingTimeInterval(0.01)
        let t4 = t1.addingTimeInterval(0.11)
        let sample = try SNTPClient.parse(reply(t2: serverT2, t3: serverT3), t1: t1, t4: t4)
        XCTAssertEqual(sample.offset, -1.0, accuracy: 1e-4)
    }

    func test_parse_rejectsBadPackets() {
        let t = Date()
        XCTAssertThrowsError(try SNTPClient.parse(Data(count: 20), t1: t, t4: t)) {
            XCTAssertEqual($0 as? SNTPClient.SNTPError, .shortResponse)
        }
        XCTAssertThrowsError(try SNTPClient.parse(reply(t2: t, t3: t, mode: 3), t1: t, t4: t)) {
            XCTAssertEqual($0 as? SNTPClient.SNTPError, .notAServerReply)
        }
        XCTAssertThrowsError(try SNTPClient.parse(reply(t2: t, t3: t, stratum: 0), t1: t, t4: t)) {
            XCTAssertEqual($0 as? SNTPClient.SNTPError, .kissOfDeath)
        }
    }
}

final class AppClockTests: XCTestCase {

    override func tearDown() {
        AppClock.shared.offset = 0
        super.tearDown()
    }

    func test_now_appliesOffset() {
        AppClock.shared.offset = 0
        let base = Date()
        AppClock.shared.offset = 3
        let shifted = AppClock.now()
        XCTAssertEqual(shifted.timeIntervalSince(base), 3, accuracy: 0.05)
        XCTAssertEqual(AppClock.corrected(base).timeIntervalSince(base), 3, accuracy: 1e-9)
    }

    func test_offset_isThreadSafe() {
        let group = DispatchGroup()
        for i in 0..<200 {
            group.enter()
            DispatchQueue.global().async {
                AppClock.shared.offset = TimeInterval(i % 5)
                _ = AppClock.now()
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertTrue((0...4).contains(Int(AppClock.shared.offset)))
    }
}
