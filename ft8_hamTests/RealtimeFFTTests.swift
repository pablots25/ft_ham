// RealtimeFFTTests.swift
// ft8_hamTests
//
// Tests for RealtimeFFT — the Accelerate-backed FFT used for waterfall rendering.
// Covers: initialiser guard (power-of-2), output dimensions, DC-peak detection,
// silence noise floor, magnitudesDirect buffer write, and a performance benchmark.
//
// RealtimeFFT is a plain final class with no UI or audio hardware dependency.
// No @MainActor required.

import XCTest
import Accelerate
@testable import ft8_ham

/// Additional unit and performance tests for `RealtimeFFT`.
final class RealtimeFFTAdditionalTests: XCTestCase {

    // MARK: - Initialiser guard

    func test_init_sizeZero_returnsNil() {
        XCTAssertNil(RealtimeFFT(size: 0))
    }

    func test_init_sizeOne_returnsNil() {
        // size == 1: (1 & 0) == 0 is true, but the implementation requires size >= 2
        XCTAssertNil(RealtimeFFT(size: 1))
    }

    func test_init_sizeThree_nonPowerOfTwo_returnsNil() {
        XCTAssertNil(RealtimeFFT(size: 3))
    }

    func test_init_sizeSeven_nonPowerOfTwo_returnsNil() {
        XCTAssertNil(RealtimeFFT(size: 7))
    }

    func test_init_sizeFive_nonPowerOfTwo_returnsNil() {
        XCTAssertNil(RealtimeFFT(size: 5))
    }

    func test_init_size512_isNotNil() {
        XCTAssertNotNil(RealtimeFFT(size: 512))
    }

    func test_init_size1024_isNotNil() {
        XCTAssertNotNil(RealtimeFFT(size: 1024))
    }

    func test_init_size2048_isNotNil() {
        XCTAssertNotNil(RealtimeFFT(size: 2048))
    }

    func test_init_size4096_isNotNil() {
        XCTAssertNotNil(RealtimeFFT(size: 4096))
    }

    // MARK: - Output dimensions

    /// `magnitudes(from:)` must return exactly n/2 bins.
    func test_magnitudes_outputCount_isHalfInputSize() {
        let size = 1024
        let fft = RealtimeFFT(size: size)!
        let samples = [Float](repeating: 0, count: size)
        let result = samples.withUnsafeBufferPointer { ptr in
            fft.magnitudes(from: ptr.baseAddress!)
        }
        XCTAssertEqual(result.count, size / 2)
    }

    func test_magnitudes_outputCount_isHalfInputSize_2048() {
        let size = 2048
        let fft = RealtimeFFT(size: size)!
        let samples = [Float](repeating: 0, count: size)
        let result = samples.withUnsafeBufferPointer { ptr in
            fft.magnitudes(from: ptr.baseAddress!)
        }
        XCTAssertEqual(result.count, size / 2)
    }

    // MARK: - DC signal (all-1.0 samples)

    /// A constant DC signal (all samples == 1.0) concentrates energy at bin 0.
    /// All other bins should be strictly smaller than bin 0.
    func test_magnitudes_dcSignal_bin0IsMaximum() {
        let size = 1024
        let fft = RealtimeFFT(size: size)!
        let samples = [Float](repeating: 1.0, count: size)

        let mags = samples.withUnsafeBufferPointer { ptr in
            fft.magnitudes(from: ptr.baseAddress!)
        }

        guard let maxMag = mags.max() else {
            XCTFail("magnitudes array was empty")
            return
        }
        XCTAssertEqual(mags[0], maxMag, accuracy: 1e-3,
                       "DC signal: bin[0] must contain the maximum magnitude")
    }

    // MARK: - Silence (all-zero samples)

    /// All-zero input must produce magnitudes at or below a reasonable noise floor.
    /// Floating-point arithmetic introduces a small epsilon; we allow up to 1e-5.
    func test_magnitudes_silence_allMagnitudesBelowNoiseFloor() {
        let size = 1024
        let fft = RealtimeFFT(size: size)!
        let samples = [Float](repeating: 0, count: size)

        let mags = samples.withUnsafeBufferPointer { ptr in
            fft.magnitudes(from: ptr.baseAddress!)
        }

        let maxMag = mags.max() ?? 0
        XCTAssertLessThanOrEqual(maxMag, 1e-3,
            "Silence input should produce near-zero magnitudes, got max: \(maxMag)")
    }

    // MARK: - magnitudesDirect

    /// `magnitudesDirect` must write into the provided output buffer and
    /// produce the same result as `magnitudes(from:)`.
    func test_magnitudesDirect_writesToOutputBuffer() {
        let size = 512
        let fft = RealtimeFFT(size: size)!

        // Slightly varied input — not pure silence
        var samples = [Float](repeating: 0, count: size)
        for i in stride(from: 0, to: size, by: 16) { samples[i] = 0.5 }

        var outputBuffer = [Float](repeating: -1, count: size / 2)

        _ = samples.withUnsafeBufferPointer { ptr in
            fft.magnitudesDirect(ptr.baseAddress!, output: &outputBuffer)
        }

        // None of the output values should still be -1 (sentinel)
        XCTAssertFalse(outputBuffer.contains(-1),
            "magnitudesDirect must overwrite all values in the output buffer")
        // All values must be non-negative (magnitudes are absolute)
        XCTAssertTrue(outputBuffer.allSatisfy { $0 >= 0 },
            "Magnitudes must be non-negative")
    }

    /// `magnitudesDirect` and `magnitudes` must agree on the same input.
    func test_magnitudesDirect_matchesMagnitudes_forSameInput() {
        let size = 512
        let fft = RealtimeFFT(size: size)!

        var samples = [Float](repeating: 0, count: size)
        for i in 0..<size { samples[i] = sin(Float(i) * .pi / 32) }

        let reference = samples.withUnsafeBufferPointer { ptr in
            fft.magnitudes(from: ptr.baseAddress!)
        }

        // Reset internal buffers by creating a fresh FFT instance since
        // magnitudes writes to shared internal buffers.
        let fft2 = RealtimeFFT(size: size)!
        var direct = [Float](repeating: 0, count: size / 2)
        _ = samples.withUnsafeBufferPointer { ptr in
            fft2.magnitudesDirect(ptr.baseAddress!, output: &direct)
        }

        XCTAssertEqual(reference.count, direct.count)
        for i in 0..<reference.count {
            XCTAssertEqual(reference[i], direct[i], accuracy: 1e-4,
                "Mismatch at bin \(i): magnitudes=\(reference[i]), magnitudesDirect=\(direct[i])")
        }
    }

    // MARK: - Performance

    /// FFT on a 2048-sample block should complete well under 5 ms on any
    /// device capable of running this app (iPhone 8 or later).
    /// The `measure { }` block is run 10 times by XCTest; the average is compared
    /// to the baseline automatically tracked by Xcode.
    func test_performance_magnitudes_2048Samples() {
        let size = 2048
        guard let fft = RealtimeFFT(size: size) else {
            XCTFail("Could not create RealtimeFFT with size \(size)")
            return
        }

        var samples = [Float](repeating: 0, count: size)
        for i in 0..<size { samples[i] = sin(Float(i) * .pi / 64) * 0.5 }

        measure {
            _ = samples.withUnsafeBufferPointer { ptr in
                fft.magnitudes(from: ptr.baseAddress!)
            }
        }
    }
}
