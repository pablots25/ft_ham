//
//  PipelinePerformanceTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 14/11/26.
//

import XCTest
@testable import ft8_ham

/// Benchmarks for the RX path: ft8_lib decode and `MessageProcessor`.
///
/// They use synthetic audio from the app's own encoder (pure DSP, no audio
/// hardware), so they run offline and give the same input every time.
///
/// How to use them to catch a slow feature:
/// 1. Run this class on one fixed device or simulator and, in Xcode's test
///    report, click "Set Baseline" on each measurement.
/// 2. Rerun on a feature branch (or with the feature's flag turned on).
///    A result past the allowed deviation fails the test.
///
/// Baselines are stored per device in the xcodeproj's xcbaselines, so only
/// compare numbers taken on the same device.
///
/// Recorded WAVs dropped into `ft8_hamTests/Performance/Fixtures/` are also
/// benchmarked (see `test_decodeRecordedFixtures`).
final class PipelinePerformanceTests: XCTestCase {

    private enum Benchmark {
        static let sampleRate = 12_000
        static let iterations = 5
        /// Stations heard in the synthetic busy slot.
        static let stationCount = 16
        static let firstFrequencyHz: Float = 300
        static let frequencyStepHz: Float = 140
        static let noiseAmplitude: Float = 0.3
        static let processorBatchSize = 60
    }

    private static let callsigns = [
        "EA1ABC", "EA4XYZ", "W1AW", "K1ABC", "G4ABC", "DL1ABC", "F5ABC", "JA1ABC",
        "VK2ABC", "PY2ABC", "I2ABC", "ON4ABC", "PA3ABC", "SM5ABC", "OH2ABC", "LZ1ABC",
    ]
    private static let grids = [
        "IN83", "IN80", "FN31", "FN42", "IO91", "JO62", "JN18", "PM95",
        "QF56", "GG66", "JN45", "JO20", "JO22", "JO89", "KP20", "KN22",
    ]

    private var metrics: [XCTMetric] {
        [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = Benchmark.iterations
        return options
    }

    // MARK: - Decode

    func test_decodeBusySlot_FT8() throws {
        try benchmarkDecode(isFT4: false)
    }

    func test_decodeBusySlot_FT4() throws {
        try benchmarkDecode(isFT4: true)
    }

    private func benchmarkDecode(isFT4: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let engine = ft8_Engine()
        let audio = try Self.busySlot(engine: engine, isFT4: isFT4)

        // A benchmark that decodes nothing measures nothing: check the input
        // first, outside the timed block.
        let decoded = engine.decodeAudioBuffer(audio, sampleRate: Double(Benchmark.sampleRate), isFT4: isFT4)
        XCTAssertGreaterThanOrEqual(
            decoded.count, Benchmark.stationCount / 2,
            "the synthetic slot should decode most of its \(Benchmark.stationCount) stations",
            file: file, line: line
        )

        measure(metrics: metrics, options: options) {
            _ = engine.decodeAudioBuffer(audio, sampleRate: Double(Benchmark.sampleRate), isFT4: isFT4)
        }
    }

    /// Benchmarks every `.wav` in the test bundle (12 kHz mono recordings of
    /// real slots). File names containing "ft4" are decoded as FT4.
    func test_decodeRecordedFixtures() throws {
        let bundle = Bundle(for: Self.self)
        let fixtures = (bundle.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "wav", subdirectory: "Fixtures") ?? [])
        let unique = Array(Set(fixtures)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !unique.isEmpty else {
            throw XCTSkip("No recorded WAV fixtures in ft8_hamTests/Performance/Fixtures")
        }

        let engine = ft8_Engine()
        measure(metrics: metrics, options: options) {
            for url in unique {
                let isFT4 = url.lastPathComponent.lowercased().contains("ft4")
                _ = engine.decode(fromWAV: url, isFT4: isFT4)
            }
        }
    }

    // MARK: - Message processing

    func test_processBusyBatch() {
        let processor = MessageProcessor()
        let batch = Self.decodedBatch(count: Benchmark.processorBatchSize)
        let txMessage = FT8Message(text: "CQ EA1ABC IN83", mode: .ft8, isTX: true)

        measure(metrics: metrics, options: options) {
            let done = expectation(description: "batch processed")
            Task {
                _ = await processor.process(
                    batch,
                    isFT4: false,
                    selectedBand: .band20m,
                    firstLoopRX: false,
                    isTX: false,
                    txMessage: txMessage,
                    existingLocators: [],
                    decodeSelfTXMessages: false
                )
                done.fulfill()
            }
            wait(for: [done], timeout: 10)
        }
    }

    // MARK: - Inputs

    /// One slot with `stationCount` stations calling CQ on distinct
    /// frequencies, plus deterministic noise.
    static func busySlot(engine: ft8_Engine, isFT4: Bool) throws -> Data {
        var mix: [Float] = []
        for index in 0..<Benchmark.stationCount {
            let message = "CQ \(callsigns[index]) \(grids[index])"
            let frequency = Benchmark.firstFrequencyHz + Float(index) * Benchmark.frequencyStepHz
            let audio = try XCTUnwrap(
                engine.generateFT8(message, frequency: frequency, isFT4: isFT4, toFile: nil),
                "no audio for '\(message)'"
            )
            let samples = audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            if mix.count < samples.count {
                mix.append(contentsOf: repeatElement(0, count: samples.count - mix.count))
            }
            for (i, sample) in samples.enumerated() {
                mix[i] += sample
            }
        }

        // Linear congruential generator: same noise on every run.
        var state: UInt32 = 0x1234_5678
        for i in mix.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            let uniform = Float(state >> 8) / Float(1 << 24) - 0.5
            mix[i] += uniform * 2 * Benchmark.noiseAmplitude
        }
        return mix.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// What ft8_lib hands to `MessageProcessor` for a busy slot.
    static func decodedBatch(count: Int) -> [[String: Any]] {
        (0..<count).map { index in
            let station = index % callsigns.count
            let other = (index + 1) % callsigns.count
            let text = index.isMultiple(of: 3)
                ? "CQ \(callsigns[station]) \(grids[station])"
                : "\(callsigns[other]) \(callsigns[station]) \(grids[station])"
            return [
                "text": text,
                "snr": Double(-20 + index % 30),
                "frequency": Double(200 + index * 40),
                "timeDelta": 0.1 * Double(index % 5),
                "ldpcErrors": 0,
            ]
        }
    }
}
