//
//  AudioManager.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 15/11/25.
//

import AVFoundation
import Combine
import Foundation
import Accelerate
import os.lock

final class AudioManager: NSObject {

    // MARK: - Loggers

    private let audioLogger = AppLogger(category: "AUDIO")

    // MARK: - Audio engine

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let inputNode: AVAudioInputNode?

    internal private(set) var micSampleRate: Double
    let sampleRate: Double
    let waterfallFFTSize: Int

    // MARK: - States

    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    private(set) var isPlaying = false {
        didSet { txStatusPublisher.send(isPlaying) }
    }

    private(set) var isListening = false {
        didSet { rxStatusPublisher.send(isListening) }
    }

    // MARK: - Digital input gain (Thread Safe)

    private let gainState: OSAllocatedUnfairLock<Double>

    private let minGain: Double = 0.1
    private let maxGain: Double = 2.0

    // MARK: - Publishers

    let audioSamplesPublisher = PassthroughSubject<[Float], Never>()
    let txStatusPublisher = PassthroughSubject<Bool, Never>()
    let rxStatusPublisher = PassthroughSubject<Bool, Never>()
    let audioErrorPublisher = PassthroughSubject<String, Never>()
    let clippingPublisher = PassthroughSubject<Bool, Never>()

    // MARK: - Preview Task

    private var fakeSamplesTask: Task<Void, Never>?

    // MARK: - Init

    init(waterfallFFTSize: Int = 1024,
         sampleRate: Double = 12000,
         initialGain: Double = 0.3) {

        self.sampleRate = sampleRate
        self.waterfallFFTSize = waterfallFFTSize
        self.gainState = OSAllocatedUnfairLock(
            initialState: min(max(initialGain, minGain), maxGain)
        )

        if isPreview {
            self.inputNode = nil
            self.micSampleRate = 44100
            super.init()
            audioLogger.log(.info, "Preview mode - AudioEngine disabled")
            return
        }

        self.inputNode = audioEngine.inputNode
        self.micSampleRate = 0

        super.init()

        guard configureAudioSession() else {
            audioLogger.log(.error, "AudioSession configuration failed — audio disabled")
            return
        }

        attachPlaybackChain()
        startEngineIfNeeded()

        audioLogger.log(
            .info,
            "AudioManager initialized with FFT size \(waterfallFFTSize), playback SR \(sampleRate)"
        )
    }

    // MARK: - Audio Session

    private func configureAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setMode(.measurement)

            // Use a realistic hardware rate; conversion happens later
            try session.setPreferredSampleRate(44100)
            try session.setActive(true)

            audioLogger.log(
                .info,
                "AVAudioSession active. HW SR: \(session.sampleRate)"
            )

            return true
        } catch {
            let msg = "Failed to configure AVAudioSession: \(error.localizedDescription)"
            audioLogger.log(.error, msg)
            audioErrorPublisher.send(msg)
            return false
        }
    }

    // MARK: - Playback Chain

    private func attachPlaybackChain() {
        guard let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else { return }

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: monoFormat)
    }

    // MARK: - Engine Control

    private func startEngineIfNeeded() {
        guard !audioEngine.isRunning else { return }

        do {
            try audioEngine.start()
            audioLogger.log(.info, "AudioEngine started")
        } catch {
            let msg = "Failed to start AudioEngine: \(error.localizedDescription)"
            audioLogger.log(.error, msg)
            audioErrorPublisher.send(msg)
        }
    }

    // MARK: - Mic Input

    @MainActor
    func startMicInput() {
        audioLogger.log(.info, "startMicInput called")

        guard !isPreview, let inputNode else {
            generateFakeSamples()
            isListening = true
            return
        }

        inputNode.removeTap(onBus: 0)

        let hwFormat = inputNode.inputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            let msg = "Invalid input format (SR: \(hwFormat.sampleRate), ch: \(hwFormat.channelCount))"
            audioLogger.log(.error, msg)
            audioErrorPublisher.send(msg)
            return
        }

        micSampleRate = hwFormat.sampleRate
        audioLogger.log(.info, "Mic format validated: \(micSampleRate) Hz")

        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(waterfallFFTSize),
            format: hwFormat
        ) { [weak self] buffer, _ in
            guard
                let self,
                let ptr = buffer.floatChannelData
            else { return }

            let frameLength = Int(buffer.frameLength)
            let inputPtr = ptr[0]

            var output = Array(repeating: Float(0), count: frameLength)
            var gain = Float(self.gainState.withLock { $0 })

            vDSP_vsmul(
                inputPtr,
                1,
                &gain,
                &output,
                1,
                vDSP_Length(frameLength)
            )

            if output.contains(where: { abs($0) >= 0.99 }) {
                self.clippingPublisher.send(true)
            }

            self.audioSamplesPublisher.send(output)
        }

        startEngineIfNeeded()
        isListening = true
    }

    @MainActor
    func stopMicInput() {
        audioLogger.log(.info, "stopMicInput called")

        if !isPreview {
            inputNode?.removeTap(onBus: 0)
        } else {
            fakeSamplesTask?.cancel()
            fakeSamplesTask = nil
        }

        isListening = false
    }

    // MARK: - Gain API

    func setInputGain(_ newValue: Double) {
        let clamped = min(max(newValue, minGain), maxGain)
        gainState.withLock { $0 = clamped }
        audioLogger.log(.info, "Input gain updated to \(clamped)")
    }

    func getCurrentInputGain() -> Double {
        gainState.withLock { $0 }
    }

// MARK: - Playback

    /// Play raw Float audioData. Audio data must be floats in native-endian IEEE754 order
    /// at the sample rate matching `self.sampleRate` (the generator/sampleRate used to configure this manager).
    func playAudio(_ audioData: Data) {
        guard !isPreview, !isPlaying else { return }

        let nSamples = audioData.count / MemoryLayout<Float>.size
        guard nSamples > 0, audioData.count % MemoryLayout<Float>.size == 0 else {
            audioLogger.log(.error, "playAudio: Invalid audio data size")
            return
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(nSamples))
        else { return }

        buffer.frameLength = AVAudioFrameCount(nSamples)

        audioData.withUnsafeBytes {
            memcpy(buffer.floatChannelData![0], $0.baseAddress!, audioData.count)
        }

        var gain = Float(gainState.withLock { min(max($0, minGain), maxGain) })
        vDSP_vsmul(buffer.floatChannelData![0], 1, &gain, buffer.floatChannelData![0], 1, vDSP_Length(nSamples))

        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async { self?.isPlaying = false }
        }

        isPlaying = true
        startEngineIfNeeded()
        playerNode.play()
        audioLogger.log(.info, "Playback started, isPlaying: \(isPlaying)")
    }

    func stopPlayback() {
        playerNode.stop()
        isPlaying = false
        audioLogger.log(.info, "Playback stopped")
    }

    // MARK: - Preview Samples

    private func generateFakeSamples() {
        fakeSamplesTask = Task { [weak self] in
            guard let self else { return }
            while self.isListening {
                let gain = Float(self.gainState.withLock { $0 })
                let samples = (0..<self.waterfallFFTSize).map {_ in 
                    Float.random(in: -0.01...0.01) * gain
                }
                self.audioSamplesPublisher.send(samples)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        fakeSamplesTask?.cancel()
        inputNode?.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        isPlaying = false
        isListening = false
    }

    deinit {
        cleanup()
    }
}
