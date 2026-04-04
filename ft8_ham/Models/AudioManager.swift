//
//  AudioManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/11/25.
//

import AVFoundation
import Combine
import Foundation
import Accelerate
import os.lock

// MARK: - Audio Manager Errors

enum AudioManagerError: LocalizedError {
    case sessionCategoryConfiguration(underlying: Error)
    case sessionModeConfiguration(underlying: Error)
    case sessionSampleRateConfiguration(underlying: Error)
    case sessionActivationFailed(underlying: Error)
    case engineStartFailed(underlying: Error)
    case tapInstallationFailed(underlying: Error)
    case invalidInputFormat(sampleRate: Double, channels: UInt32)
    case audioGenerationFailed(message: String)
    case invalidAudioData
    
    var errorDescription: String? {
        switch self {
        case .sessionCategoryConfiguration(let error):
            return "Failed to configure audio session category: \(error.localizedDescription)"
        case .sessionModeConfiguration(let error):
            return "Failed to configure audio session mode: \(error.localizedDescription)"
        case .sessionSampleRateConfiguration(let error):
            return "Failed to set preferred sample rate: \(error.localizedDescription)"
        case .sessionActivationFailed(let error):
            return "Failed to activate audio session: \(error.localizedDescription)"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .tapInstallationFailed(let error):
            return "Failed to install microphone tap: \(error.localizedDescription)"
        case .invalidInputFormat(let sr, let ch):
            return "Invalid input format (SR: \(sr), channels: \(ch))"
        case .audioGenerationFailed(let message):
            return "Failed to generate audio for: \(message)"
        case .invalidAudioData:
            return "Invalid audio data size or format"
        }
    }
}

final class AudioManager: NSObject, AudioManaging {

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

    private var environment: AppEnvironment { AppEnvironment.current }

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

    // MARK: - Pre-allocated buffers for audio processing (avoids allocations in hot path)
    
    private let micBufferState: OSAllocatedUnfairLock<[Float]>
    private let clippingThreshold: Float = 0.99

    // MARK: - Engine failure tracking (reduces Crashlytics noise)

    private var engineStartFailureLogged = false

    // MARK: - Preview Task

    private var fakeSamplesTask: Task<Void, Never>?

    // MARK: - Init

    init(waterfallFFTSize: Int = 1024,
         sampleRate: Double = 12000,
         initialGain: Double = 0.3,
         isTestMode: Bool = false) {

        self.sampleRate = sampleRate
        self.waterfallFFTSize = waterfallFFTSize
        self.gainState = OSAllocatedUnfairLock(
            initialState: min(max(initialGain, minGain), maxGain)
        )
        
        // Pre-allocate mic buffer (always, to satisfy Swift init requirements)
        self.micBufferState = OSAllocatedUnfairLock(
            initialState: [Float](repeating: 0, count: waterfallFFTSize)
        )

        // Test mode skips all audio initialization
        if isTestMode {
            self.inputNode = nil
            self.micSampleRate = 44100
            super.init()
            audioLogger.log(.info, "Test mode - AudioEngine disabled")
            return
        }
        
        // Use static environment check before super.init()
        let currentEnv = AppEnvironment.current
        
        if currentEnv.shouldDisableAudio {
            self.inputNode = nil
            self.micSampleRate = 44100
            super.init()
            audioLogger.log(.info, "\(currentEnv) mode - AudioEngine disabled")
            return
        }

        self.inputNode = audioEngine.inputNode
        self.micSampleRate = 0

        super.init()

        do {
            try configureAudioSession()
        } catch {
            audioLogger.log(.error, "AudioSession configuration failed: \(error.localizedDescription)")
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        attachPlaybackChain()

        do {
            try startEngineIfNeeded()
        } catch {
            audioLogger.log(.warning, "Engine not started during init (will retry): \(error.localizedDescription)")
        }

        observeAudioSessionInterruptions()

        audioLogger.log(
            .info,
            "AudioManager initialized with FFT size \(waterfallFFTSize), playback SR \(sampleRate)"
        )
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP
                ]
            )
        } catch {
            throw AudioManagerError.sessionCategoryConfiguration(underlying: error)
        }
        
        do {
            try session.setMode(.measurement)
        } catch {
            throw AudioManagerError.sessionModeConfiguration(underlying: error)
        }

        do {
            try session.setPreferredSampleRate(44100)
        } catch {
            throw AudioManagerError.sessionSampleRateConfiguration(underlying: error)
        }
        
        do {
            try session.setActive(true)
        } catch {
            throw AudioManagerError.sessionActivationFailed(underlying: error)
        }

        audioLogger.log(
            .info,
            "AVAudioSession active. HW SR: \(session.sampleRate)"
        )
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

    private func startEngineIfNeeded() throws {
        guard !audioEngine.isRunning else {
            engineStartFailureLogged = false
            return
        }

        do {
            try audioEngine.start()
            audioLogger.log(.info, "AudioEngine started")
            engineStartFailureLogged = false
        } catch {
            let wrappedError = AudioManagerError.engineStartFailed(underlying: error)
            audioErrorPublisher.send(wrappedError.localizedDescription)

            // Only log as .error (→ Crashlytics non-fatal) on the first failure
            if !engineStartFailureLogged {
                audioLogger.log(.error, wrappedError.localizedDescription)
                engineStartFailureLogged = true
            } else {
                audioLogger.log(.warning, "Engine start still failing: \(wrappedError.localizedDescription)")
            }

            throw wrappedError
        }
    }

    // MARK: - Mic Input

    @MainActor
    func startMicInput() {
        audioLogger.log(.info, "startMicInput called")

        guard !environment.shouldDisableAudio, let inputNode else {
            generateFakeSamples()
            isListening = true
            return
        }

        // Ensure engine is started BEFORE attempting to tap
        do {
            try startEngineIfNeeded()
        } catch {
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        // Remove any existing tap
        inputNode.removeTap(onBus: 0)

        let hwFormat = inputNode.inputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            let error = AudioManagerError.invalidInputFormat(
                sampleRate: hwFormat.sampleRate,
                channels: hwFormat.channelCount
            )
            audioLogger.log(.error, error.localizedDescription)
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        micSampleRate = hwFormat.sampleRate
        audioLogger.log(.info, "Mic format validated: \(micSampleRate) Hz")

        do {
            try installInputTap(on: inputNode, format: hwFormat)
            isListening = true
            audioLogger.log(.info, "Mic input tap installed successfully")
        } catch {
            audioLogger.log(.error, "Failed to install input tap: \(error.localizedDescription)")
            audioErrorPublisher.send("Failed to start microphone: \(error.localizedDescription)")
            isListening = false
        }
    }

    private func installInputTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) throws {
        do {
            try inputNode.installTap(
                onBus: 0,
                bufferSize: AVAudioFrameCount(waterfallFFTSize),
                format: format
            ) { [weak self] buffer, _ in
                guard
                    let self,
                    let ptr = buffer.floatChannelData
                else { return }

                let frameLength = Int(buffer.frameLength)
                let inputPtr = ptr[0]
                let gain = Float(self.gainState.withLock { $0 })
                
                // Use pre-allocated buffer, resizing only if needed
                let output: [Float] = self.micBufferState.withLock { buffer in
                    // Resize buffer if frame size changed (rare)
                    if buffer.count < frameLength {
                        buffer = [Float](repeating: 0, count: frameLength)
                    }
                    
                    // Apply gain using vDSP (in-place style with pre-allocated buffer)
                    var mutableGain = gain
                    vDSP_vsmul(
                        inputPtr,
                        1,
                        &mutableGain,
                        &buffer,
                        1,
                        vDSP_Length(frameLength)
                    )
                    
                    // Return slice of buffer matching actual frame length
                    return Array(buffer.prefix(frameLength))
                }

                // Optimized clipping detection using vDSP
                var maxVal: Float = 0
                vDSP_maxmgv(output, 1, &maxVal, vDSP_Length(frameLength))
                if maxVal >= self.clippingThreshold {
                    self.clippingPublisher.send(true)
                }

                self.audioSamplesPublisher.send(output)
            }
        } catch {
            throw AudioManagerError.tapInstallationFailed(underlying: error)
        }
    }

    @MainActor
    func stopMicInput() {
        audioLogger.log(.info, "stopMicInput called")

        if !environment.shouldDisableAudio {
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
        guard !environment.shouldDisableAudio, !isPlaying else { return }

        let nSamples = audioData.count / MemoryLayout<Float>.size
        guard nSamples > 0, audioData.count % MemoryLayout<Float>.size == 0 else {
            let error = AudioManagerError.invalidAudioData
            audioLogger.log(.error, error.localizedDescription)
            audioErrorPublisher.send(error.localizedDescription)
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

        do {
            try startEngineIfNeeded()
        } catch {
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async { self?.isPlaying = false }
        }

        isPlaying = true
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

    // MARK: - Audio Session Interruption Recovery

    private func observeAudioSessionInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            audioLogger.log(.info, "Audio session interrupted")
        case .ended:
            let shouldResume = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false

            if shouldResume {
                audioLogger.log(.info, "Audio session interruption ended — resuming engine")
                do {
                    try configureAudioSession()
                    try startEngineIfNeeded()
                } catch {
                    audioLogger.log(.error, "Failed to recover from interruption: \(error.localizedDescription)")
                    audioErrorPublisher.send(error.localizedDescription)
                }
            } else {
                audioLogger.log(.info, "Audio session interruption ended — not resuming")
            }
        @unknown default:
            break
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        fakeSamplesTask?.cancel()
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
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
