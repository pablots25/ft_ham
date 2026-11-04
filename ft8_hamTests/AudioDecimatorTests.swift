//
//  AudioDecimatorTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 17/9/26.
//

import XCTest
@testable import ft8_ham

final class AudioDecimatorTests: XCTestCase {

    private func sine(hz: Double, frames: Int, sampleRate: Double) -> [Float] {
        (0 ..< frames).map { Float(sin(2 * .pi * hz * Double($0) / sampleRate)) }
    }

    /// Goertzel power at `hz` — enough to check a tone survived resampling.
    private func power(of samples: ArraySlice<Float>, hz: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * hz / sampleRate
        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        for x in samples {
            s0 = Double(x) + 2 * cos(w) * s1 - s2
            s2 = s1; s1 = s0
        }
        return (s1 * s1 + s2 * s2 - 2 * cos(w) * s1 * s2) / Double(samples.count)
    }

    func test_rejectsInvalidRates() {
        XCTAssertNil(AudioDecimator(inputRate: 0, outputRate: 12_000))
        XCTAssertNil(AudioDecimator(inputRate: 44_100, outputRate: -1))
    }

    /// 44.1 kHz → 12 kHz is a non-integer ratio; the output must keep the
    /// tone, keep the length ratio, and join buffers without gaps.
    func test_streamsAToneAcrossBuffers() {
        guard let decimator = AudioDecimator(inputRate: 44_100, outputRate: 12_000) else {
            return XCTFail("converter not available")
        }
        let toneHz = 1500.0
        let input = sine(hz: toneHz, frames: 44_100, sampleRate: 44_100)   // 1 s

        var output: [Float] = []
        for start in stride(from: 0, to: input.count, by: 2048) {
            let end = min(start + 2048, input.count)
            input[start ..< end].withUnsafeBufferPointer { output += decimator.process($0) }
        }

        // ~12 000 frames out, minus a little filter latency still buffered.
        XCTAssertGreaterThan(output.count, 11_800)
        XCTAssertLessThanOrEqual(output.count, 12_000 + 64)

        // Skip the start-up transient, then the tone must dominate.
        let body = output[2000 ..< 11_000]
        let atTone = power(of: body, hz: toneHz, sampleRate: 12_000)
        let offTone = power(of: body, hz: 2500, sampleRate: 12_000)
        XCTAssertGreaterThan(atTone, 0.1)
        XCTAssertGreaterThan(atTone / max(offTone, 1e-12), 1000, "≥ 30 dB tone-to-off-tone")

        // No discontinuity between buffers: consecutive samples of a 1500 Hz
        // tone at 12 kHz never jump by more than the tone's own slope.
        let maxStep = zip(body, body.dropFirst()).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxStep, 0.75, "2·sin(π·1500/12000) ≈ 0.71 is the largest legitimate step")
    }

    func test_handlesBuffersLargerThanTheInitialCapacity() {
        guard let decimator = AudioDecimator(inputRate: 48_000, outputRate: 12_000) else {
            return XCTFail("converter not available")
        }
        let input = sine(hz: 1000, frames: 9600, sampleRate: 48_000)
        let out = input.withUnsafeBufferPointer { decimator.process($0) }
        XCTAssertGreaterThan(out.count, 2300)
        XCTAssertLessThanOrEqual(out.count, 2400 + 64)
    }
}
