//
//  RealtimeFFT.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/11/25.
//

import Accelerate

final class RealtimeFFT {
    let log2n: vDSP_Length
    let n: Int
    private let fftSetup: FFTSetup
    private var window: [Float]
    /// Turns raw `vDSP_zvabs` output into dBFS-referenced amplitude: a full-scale
    /// sine reads 1.0 (0 dBFS) in its peak bin. Unnormalised, the same tone lands
    /// at `windowSum / 2` — about +58 dB for N = 2048 — so every downstream dB
    /// threshold would have to be calibrated to an FFT-size-dependent number.
    private let magnitudeScale: Float

    // Buffers reused
    private var real: UnsafeMutablePointer<Float>
    private var imag: UnsafeMutablePointer<Float>

    init?(size: Int) {
        guard size >= 2, (size & (size - 1)) == 0 else { return nil } // power of two
        n = size
        log2n = vDSP_Length(log2(Double(size)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        fftSetup = setup

        // Create Hann window
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        magnitudeScale = 2 / window.reduce(0, +)

        real = UnsafeMutablePointer<Float>.allocate(capacity: size)
        imag = UnsafeMutablePointer<Float>.allocate(capacity: size)
        imag.initialize(repeating: 0, count: size)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        real.deinitialize(count: n)
        imag.deinitialize(count: n)
        real.deallocate()
        imag.deallocate()
    }

    // Input: samples length == n, returns magnitudes length n/2
    func magnitudes(from samples: UnsafePointer<Float>) -> [Float] {
        // Copy + window
        vDSP_vmul(samples, 1, window, 1, real, 1, vDSP_Length(n))
        // imag already zeroed except maybe previous content -> ensure zero
        imag.initialize(repeating: 0, count: n)

        var split = DSPSplitComplex(realp: real, imagp: imag)
        vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        let half = n / 2
        var mags = [Float](repeating: 0, count: half)
        vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
        normalise(&mags, count: half)
        return mags
    }

    func magnitudesDirect(_ samples: UnsafePointer<Float>, output: inout [Float]) -> [Float] {
        // Copy and apply window
        vDSP_vmul(samples, 1, window, 1, real, 1, vDSP_Length(n))
        imag.initialize(repeating: 0, count: n)

        var split = DSPSplitComplex(realp: real, imagp: imag)
        vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        // Write magnitudes directly to output
        let half = n / 2
        vDSP_zvabs(&split, 1, &output, 1, vDSP_Length(half))
        normalise(&output, count: half)
        return output
    }

    private func normalise(_ mags: inout [Float], count: Int) {
        var scale = magnitudeScale
        mags.withUnsafeMutableBufferPointer { p in
            vDSP_vsmul(p.baseAddress!, 1, &scale, p.baseAddress!, 1, vDSP_Length(count))
        }
    }
}
