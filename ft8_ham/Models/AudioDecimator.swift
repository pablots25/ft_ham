//
//  AudioDecimator.swift
//  ft_ham
//
//  Created by Pablo Turrion on 17/9/26.
//

import AVFoundation

/// Streams mono float audio from one sample rate to another.
///
/// The microphone runs at the hardware rate (44.1 or 48 kHz) while the FT8
/// decoder and waterfall are specified at 12 kHz. Converting once, as the
/// audio arrives, lets every consumer work on a quarter of the samples and
/// removes the sample-rate dependence from the DSP downstream.
///
/// Wraps `AVAudioConverter`, which keeps its filter state between calls so
/// consecutive buffers join without a discontinuity. Not thread-safe: call
/// `process` from one thread (the audio tap).
final class AudioDecimator {
    let inputRate: Double
    let outputRate: Double

    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private var inputBuffer: AVAudioPCMBuffer
    private var outputBuffer: AVAudioPCMBuffer

    /// - Returns: `nil` when the formats cannot be built or converted between.
    init?(inputRate: Double, outputRate: Double) {
        guard
            inputRate > 0, outputRate > 0,
            let inFormat = AVAudioFormat(standardFormatWithSampleRate: inputRate, channels: 1),
            let outFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1),
            let converter = AVAudioConverter(from: inFormat, to: outFormat),
            let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 4096),
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormat,
                frameCapacity: AudioDecimator.outputCapacity(forInputFrames: 4096, ratio: outputRate / inputRate)
            )
        else { return nil }

        self.inputRate = inputRate
        self.outputRate = outputRate
        self.inputFormat = inFormat
        self.outputFormat = outFormat
        self.converter = converter
        self.inputBuffer = inBuffer
        self.outputBuffer = outBuffer
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    }

    private static func outputCapacity(forInputFrames frames: Int, ratio: Double) -> AVAudioFrameCount {
        AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
    }

    /// Converts one buffer. Output length is about `count × outputRate / inputRate`;
    /// a few frames of filter latency shift between calls.
    func process(_ samples: UnsafeBufferPointer<Float>) -> [Float] {
        let frames = samples.count
        guard frames > 0, let base = samples.baseAddress else { return [] }

        if inputBuffer.frameCapacity < AVAudioFrameCount(frames) {
            guard
                let inBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frames)),
                let outBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: Self.outputCapacity(forInputFrames: frames, ratio: outputRate / inputRate)
                )
            else { return [] }
            inputBuffer = inBuffer
            outputBuffer = outBuffer
        }

        inputBuffer.frameLength = AVAudioFrameCount(frames)
        inputBuffer.floatChannelData![0].update(from: base, count: frames)
        outputBuffer.frameLength = 0

        // Hand the converter this one buffer, then report "no more for now" so
        // it flushes what it can without discarding its state (`.endOfStream`
        // would reset the filter and click at every buffer boundary).
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return self.inputBuffer
        }
        guard status != .error, error == nil, let out = outputBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: out[0], count: Int(outputBuffer.frameLength)))
    }
}
