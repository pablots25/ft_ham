//
//  AudioManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/11/25.
//

import AVFoundation
import Combine
import UIKit
import Foundation
import Accelerate
import os.lock

// MARK: - Gain limits

/// Bounds shared by `AudioManager`, `FT8ViewModel` and the settings sliders so
/// the clamp is defined once.
enum AudioGainLimits {
    /// RX floor is −40 dB. An external USB/line sound card feeds the input far
    /// hotter than the built-in mic, and the previous −20 dB floor was not
    /// enough attenuation to keep it out of clipping.
    static let minInput: Double = 0.01
    static let maxInput: Double = 2.0

    static let minOutput: Double = 0.1
    static let maxOutput: Double = 2.0
}

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

    /// Hardware rate of the microphone. Audio is decimated to `sampleRate`
    /// before it is published, so consumers never see this rate.
    internal private(set) var micSampleRate: Double
    /// Rate of the audio this manager publishes (`audioSamplesPublisher`) and
    /// plays back: the 12 kHz the FT8 engine is specified at.
    let sampleRate: Double
    let waterfallFFTSize: Int
    /// Converts the microphone rate to `sampleRate`; rebuilt with every tap.
    private var decimator: AudioDecimator?

    // MARK: - States

    private var environment: AppEnvironment { AppEnvironment.current }

    private(set) var isPlaying = false {
        didSet { txStatusPublisher.send(isPlaying) }
    }

    private(set) var isListening = false {
        didSet { rxStatusPublisher.send(isListening) }
    }

    /// `true` once `configureAudioSession()` has succeeded. Activation can fail
    /// at launch (a phone call or another app holds the session), so every
    /// entry point that needs audio retries the setup while this is `false`.
    private(set) var isSessionConfigured = false

    /// `true` between `startMicInput()` and `stopMicInput()`, even when the tap
    /// could not be installed. Recovery paths use it to bring RX back.
    private(set) var wantsMicInput = false

    // MARK: - Digital input gain (Thread Safe)

    private let gainState: OSAllocatedUnfairLock<Double>

    private let minGain: Double = AudioGainLimits.minInput
    private let maxGain: Double = AudioGainLimits.maxInput

    // MARK: - TX output gain (Thread Safe)

    private let outputGainState: OSAllocatedUnfairLock<Double>

    private let minOutputGain: Double = AudioGainLimits.minOutput
    private let maxOutputGain: Double = AudioGainLimits.maxOutput

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

    // MARK: - Route-change re-entrancy guard

    /// `true` while `reconfigureEngineAfterRouteChange()` is executing.
    /// Prevents the feedback loop where `configureAudioSession()` triggers
    /// `.categoryChange` / `.override` route-change notifications that would
    /// re-enter the same reconfiguration path.
    /// `internal(set)` so unit tests can seed the flag.
    var isReconfiguring = false

    /// Minimum interval between successive reconfigurations to debounce
    /// rapid-fire route change notifications from the OS.
    private let routeChangeDebounceInterval: TimeInterval = 0.5
    /// Timestamp of the last successful reconfiguration entry.
    /// `internal(set)` so unit tests can seed the date.
    var lastRouteChangeDate: Date = .distantPast

    /// Date of the first engine-start failure in the current failure run.
    /// `nil` means no active failure run. Only reset after a full successful playback,
    /// not just after a transient engine start (which avoids re-logging on every TX slot).
    /// `internal` so unit tests can seed the date without hitting AVAudioEngine.
    var engineStartFirstFailureDate: Date?
    private let engineStartErrorCooldown: TimeInterval = 5 * 60   // 5 min

    /// Returns `true` when a new Crashlytics non-fatal should be recorded for an
    /// engine-start failure. `false` means the error is within the suppression window.
    /// Exposed as `internal` for deterministic unit testing.
    func shouldRecordEngineStartError(at date: Date = Date()) -> Bool {
        guard let firstFailure = engineStartFirstFailureDate,
              date.timeIntervalSince(firstFailure) < engineStartErrorCooldown
        else {
            return true
        }
        return false
    }

    // MARK: - Preview Task

    private var fakeSamplesTask: Task<Void, Never>?

    // MARK: - Init

    init(waterfallFFTSize: Int = 1024,
         sampleRate: Double = 12000,
         initialGain: Double = 0.3,
         initialOutputGain: Double = 1.0,
         isTestMode: Bool = false) {

        self.sampleRate = sampleRate
        self.waterfallFFTSize = waterfallFFTSize
        self.gainState = OSAllocatedUnfairLock(
            initialState: min(max(initialGain, minGain), maxGain)
        )
        self.outputGainState = OSAllocatedUnfairLock(
            initialState: min(max(initialOutputGain, minOutputGain), maxOutputGain)
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

        // The playback chain and the observers must exist even when the session
        // cannot be activated yet. Bailing out here left the player node
        // unattached (stereo by default), and the first TX then crashed in
        // scheduleBuffer on a channel count mismatch.
        attachPlaybackChain()

        do {
            try configureSessionIfNeeded()
            try startEngineIfNeeded()
        } catch {
            audioLogger.log(.warning, "Audio not ready during init (will retry): \(error.localizedDescription)")
            audioErrorPublisher.send(error.localizedDescription)
        }

        observeAudioSessionInterruptions()
        observeAudioSessionRouteChanges()
        observeEngineConfigurationChanges()
        observeAppDidBecomeActive()

        audioLogger.log(
            .info,
            "AudioManager initialized with FFT size \(waterfallFFTSize), playback SR \(sampleRate)"
        )
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        isSessionConfigured = false
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP,
                    .allowAirPlay
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

        isSessionConfigured = true
        audioLogger.log(
            .info,
            "AVAudioSession active. HW SR: \(session.sampleRate)"
        )
    }

    /// Configures the session only when an earlier attempt failed or none ran.
    /// A failure here is an expected OS condition (call in progress, another
    /// app owns the session), so it is a warning rather than a non-fatal.
    private func configureSessionIfNeeded() throws {
        guard !isSessionConfigured else { return }
        do {
            try configureAudioSession()
        } catch {
            audioLogger.log(.warning, "Audio session not available: \(error.localizedDescription)")
            throw error
        }
    }

    /// Brings the session and the engine up, whichever of them is missing.
    private func ensureSessionAndEngine() throws {
        try configureSessionIfNeeded()
        try startEngineIfNeeded()
    }

    // MARK: - Playback Chain

    /// Attaches the player node (if needed) and connects it in mono to the
    /// main mixer. Safe to call again to repair a broken chain.
    private func attachPlaybackChain() {
        guard let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else { return }

        if playerNode.engine == nil {
            audioEngine.attach(playerNode)
        }
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: monoFormat)
    }

    /// `true` when scheduling a buffer on the player would raise an
    /// NSException: the node is not in the engine, or its output channel
    /// count differs from the buffer's.
    static func playbackChainNeedsRepair(
        isAttached: Bool,
        playerChannels: AVAudioChannelCount,
        bufferChannels: AVAudioChannelCount
    ) -> Bool {
        !isAttached || playerChannels != bufferChannels
    }

    // MARK: - Engine Control

    private func startEngineIfNeeded() throws {
        guard !audioEngine.isRunning else { return }

        do {
            try audioEngine.start()
            audioLogger.log(.info, "AudioEngine started")
            // Do NOT clear engineStartFirstFailureDate here — a transient start during
            // interruption recovery should not re-arm the Crashlytics gate. It is cleared
            // only after a complete successful playback (see playAudio).
        } catch {
            let wrappedError = AudioManagerError.engineStartFailed(underlying: error)
            audioErrorPublisher.send(wrappedError.localizedDescription)

            if shouldRecordEngineStartError() {
                // First failure (or cooldown expired) — record to Crashlytics once
                audioLogger.log(.error, wrappedError.localizedDescription)
                engineStartFirstFailureDate = Date()
            } else {
                // Within cooldown window — suppress Crashlytics, log locally only
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

        wantsMicInput = true

        // Ensure session and engine are up BEFORE attempting to tap
        do {
            try ensureSessionAndEngine()
        } catch {
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        // Remove any existing tap
        inputNode.removeTap(onBus: 0)

        guard installMicTap(on: inputNode) else {
            isListening = false
            return
        }
        isListening = true
        audioLogger.log(.info, "Mic input tap installed successfully")
    }

    /// Formats to try for the input tap, in order. AVFoundation requires the
    /// tap rate to equal the hardware input rate, so the hardware-side
    /// `inputFormat` goes first. After a route change the node's
    /// `outputFormat` can keep the old rate for a while, and tapping with it
    /// failed with "format.sampleRate == inputHWFormat.sampleRate" (1.3.0 build
    /// 15). It stays as a second attempt for the case where the input side is
    /// rejected instead. Invalid (0 Hz / 0 channel) formats and duplicates are
    /// dropped.
    static func tapFormatCandidates(input: AVAudioFormat, output: AVAudioFormat) -> [AVAudioFormat] {
        var candidates: [AVAudioFormat] = []
        for format in [input, output] where format.sampleRate > 0 && format.channelCount > 0 {
            let isDuplicate = candidates.contains {
                $0.sampleRate == format.sampleRate && $0.channelCount == format.channelCount
            }
            if !isDuplicate { candidates.append(format) }
        }
        return candidates
    }

    /// Installs the mic tap with the first candidate format the node accepts.
    /// Returns `false` when none worked; the error is already logged and published.
    private func installMicTap(on inputNode: AVAudioInputNode) -> Bool {
        let input = inputNode.inputFormat(forBus: 0)
        let candidates = Self.tapFormatCandidates(
            input: input,
            output: inputNode.outputFormat(forBus: 0)
        )

        guard !candidates.isEmpty else {
            let error = AudioManagerError.invalidInputFormat(
                sampleRate: input.sampleRate,
                channels: input.channelCount
            )
            audioLogger.log(.error, error.localizedDescription)
            audioErrorPublisher.send(error.localizedDescription)
            return false
        }

        var lastError: Error = AudioManagerError.invalidInputFormat(
            sampleRate: input.sampleRate,
            channels: input.channelCount
        )
        for format in candidates {
            do {
                try installInputTap(on: inputNode, format: format)
                micSampleRate = format.sampleRate
                audioLogger.log(.info, "Mic tap installed at \(format.sampleRate) Hz")
                return true
            } catch {
                lastError = error
                audioLogger.log(.warning, "Mic tap rejected at \(format.sampleRate) Hz: \(error.localizedDescription)")
            }
        }

        let wrapped = AudioManagerError.tapInstallationFailed(underlying: lastError)
        audioLogger.log(.error, wrapped.localizedDescription)
        audioErrorPublisher.send(wrapped.localizedDescription)
        return false
    }

    /// Installs the mic tap with `format`, or throws without touching the
    /// current decimator.
    private func installInputTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) throws {
        // Identity rates need no converter; anything else goes through one.
        let decimator = format.sampleRate == sampleRate
            ? nil
            : AudioDecimator(inputRate: format.sampleRate, outputRate: sampleRate)
        if format.sampleRate != sampleRate && decimator == nil {
            throw AudioManagerError.invalidInputFormat(
                sampleRate: format.sampleRate,
                channels: format.channelCount
            )
        }

        // installTap raises an NSException (e.g. -10868, or a sample rate that
        // does not match the hardware). Swift cannot catch it, so route it
        // through the catcher.
        try ObjCExceptionCatcher.catchException {
            self.installTapBlock(on: inputNode, format: format, decimator: decimator)
        }
        self.decimator = decimator
    }

    private func installTapBlock(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        decimator: AudioDecimator?
    ) {
        inputNode.installTap(
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

                // Publish at `sampleRate`: decimate unless the mic already runs there.
                if let decimator {
                    let resampled = output.withUnsafeBufferPointer { decimator.process($0) }
                    if !resampled.isEmpty {
                        self.audioSamplesPublisher.send(resampled)
                    }
                } else {
                    self.audioSamplesPublisher.send(output)
                }
            }
    }

    @MainActor
    func stopMicInput() {
        audioLogger.log(.info, "stopMicInput called")
        wantsMicInput = false

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

    func setOutputGain(_ newValue: Double) {
        let clamped = min(max(newValue, minOutputGain), maxOutputGain)
        outputGainState.withLock { $0 = clamped }
        audioLogger.log(.info, "TX output gain updated to \(clamped)")
    }

    func getCurrentOutputGain() -> Double {
        outputGainState.withLock { $0 }
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

        _ = audioData.withUnsafeBytes {
            memcpy(buffer.floatChannelData![0], $0.baseAddress!, audioData.count)
        }

        var gain = Float(outputGainState.withLock { min(max($0, minOutputGain), maxOutputGain) })
        vDSP_vsmul(buffer.floatChannelData![0], 1, &gain, buffer.floatChannelData![0], 1, vDSP_Length(nSamples))

        // Reactivate session before engine start — recovers from interruptions
        // where the session became inactive between slots. This fails while the
        // app is backgrounded; in that case the engine has no IO cycle and
        // -[AVAudioPlayerNode play] would throw, so abort instead of crashing.
        do {
            try configureSessionIfNeeded()
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            audioLogger.log(.warning, "Audio session activation failed, skipping playback: \(error.localizedDescription)")
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        do {
            try startEngineIfNeeded()
        } catch {
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        guard audioEngine.isRunning else {
            let message = "Audio engine not running after start, skipping playback"
            audioLogger.log(.error, message)
            audioErrorPublisher.send(message)
            return
        }

        if Self.playbackChainNeedsRepair(
            isAttached: playerNode.engine != nil,
            playerChannels: playerNode.outputFormat(forBus: 0).channelCount,
            bufferChannels: buffer.format.channelCount
        ) {
            audioLogger.log(.warning, "Playback chain not ready, reattaching the player node")
            attachPlaybackChain()
        }

        // scheduleBuffer raises an NSException on a channel count mismatch or a
        // detached node. Catch it so a broken chain skips this TX instead of
        // crashing the app.
        do {
            try ObjCExceptionCatcher.catchException {
                self.playerNode.scheduleBuffer(buffer) { [weak self] in
                    DispatchQueue.main.async {
                        self?.isPlaying = false
                        // Playback completed successfully — reset the failure gate so a future
                        // genuine engine failure gets a fresh Crashlytics event.
                        self?.engineStartFirstFailureDate = nil
                    }
                }
            }
        } catch {
            audioLogger.log(.error, "playerNode.scheduleBuffer threw: \(error.localizedDescription)")
            audioErrorPublisher.send(error.localizedDescription)
            return
        }

        // play() raises an NSException ("player did not see an IO cycle") when the
        // engine is not actually rendering — e.g. started while backgrounded. Swift
        // cannot catch NSExceptions, so route the call through ObjCExceptionCatcher.
        do {
            try ObjCExceptionCatcher.catchException { self.playerNode.play() }
            isPlaying = true
            audioLogger.log(.info, "Playback started, isPlaying: \(isPlaying)")
        } catch {
            playerNode.stop()
            isPlaying = false
            audioLogger.log(.error, "playerNode.play() threw: \(error.localizedDescription)")
            audioErrorPublisher.send(error.localizedDescription)
        }
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

    // MARK: - Audio Route Change Recovery

    private func observeAudioSessionRouteChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    /// Exposed as `internal` for deterministic unit testing. Do not call from app code.
    @objc func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        // Dispatch to main actor to safely access isListening and other mutable state.
        Task { @MainActor [weak self] in
            self?.handleRouteChange(reason: reason)
        }
    }

    /// Exposed as `internal` for deterministic unit testing. Do not call from app code.
    @MainActor
    func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        switch reason {
        case .newDeviceAvailable:
            reconfigureEngineAfterRouteChange(reason: "new device available")
        case .oldDeviceUnavailable:
            reconfigureEngineAfterRouteChange(reason: "device removed")
        case .wakeFromSleep:
            reconfigureEngineAfterRouteChange(reason: "wake from sleep")
        case .categoryChange, .override:
            reconfigureEngineAfterRouteChange(reason: "category/override change")
        case .noSuitableRouteForCategory:
            audioLogger.log(.warning, "Audio route: no suitable route for current session category")
            audioErrorPublisher.send("No audio output available. Check your audio device connection.")
        default:
            audioLogger.log(.debug, "Audio route changed (reason: \(reason.rawValue)) — ignored")
        }
    }

    /// Stops the mic tap, reconfigures the session, and restarts the engine,
    /// then reinstalls the tap using the new hardware format. Called after any
    /// route change or AVAudioEngine I/O configuration change.
    /// Exposed as `internal` for deterministic unit testing. Do not call from app code.
    @MainActor
    func reconfigureEngineAfterRouteChange(reason: String = "unknown") {
        guard !environment.shouldDisableAudio, inputNode != nil else { return }

        // Prevent re-entrant calls: configureAudioSession() sets category/mode/active
        // which fires new .categoryChange/.override route-change notifications.
        guard !isReconfiguring else {
            audioLogger.log(.debug, "Audio route: \(reason) — skipped (reconfiguration in progress)")
            return
        }

        // Debounce rapid-fire notifications from the OS.
        let now = Date()
        guard now.timeIntervalSince(lastRouteChangeDate) >= routeChangeDebounceInterval else {
            audioLogger.log(.debug, "Audio route: \(reason) — debounced")
            return
        }
        lastRouteChangeDate = now
        isReconfiguring = true
        defer { isReconfiguring = false }

        audioLogger.log(.info, "Audio route: \(reason) — reconfiguring engine")

        let wasListening = isListening || wantsMicInput

        if wasListening {
            inputNode?.removeTap(onBus: 0)
        }

        do {
            try configureAudioSession()
            try startEngineIfNeeded()
        } catch {
            audioLogger.log(.warning, "Failed to reconfigure after route change: \(error.localizedDescription)")
            audioErrorPublisher.send(error.localizedDescription)
            // The tap is gone; let recoverAudioIfNeeded() reinstall it later.
            if wasListening { isListening = false }
            return
        }

        guard wasListening, let inputNode else { return }

        audioLogger.log(.info, "Reinstalling mic tap after route change")
        isListening = installMicTap(on: inputNode)
    }

    // MARK: - App Lifecycle Recovery

    private func observeAppDidBecomeActive() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.recoverAudioIfNeeded()
        }
    }

    /// Retries the audio setup when the app comes back to the foreground after
    /// the session could not be activated (typically a call at launch), and
    /// brings RX back if it was requested in the meantime.
    /// Exposed as `internal` for deterministic unit testing. Do not call from app code.
    @MainActor
    func recoverAudioIfNeeded() {
        guard !environment.shouldDisableAudio, inputNode != nil else { return }
        guard !isSessionConfigured || (wantsMicInput && !isListening) else { return }

        audioLogger.log(.info, "App active, retrying audio setup")
        do {
            try ensureSessionAndEngine()
        } catch {
            return
        }

        if wantsMicInput && !isListening {
            startMicInput()
        }
    }

    // MARK: - Engine Configuration Change Recovery

    private func observeEngineConfigurationChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: audioEngine
        )
    }

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.reconfigureEngineAfterRouteChange(reason: "engine hardware config change")
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

    /// Exposed as `internal` for deterministic unit testing. Do not call from app code.
    @objc func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            if #available(iOS 14.5, *) {
                if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
                   let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue),
                   reason == .builtInMicMuted {
                    audioLogger.log(.info, "Audio session interrupted — built-in microphone muted by hardware switch")
                    return
                }
            }
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
                    audioLogger.log(.warning, "Failed to recover from interruption: \(error.localizedDescription)")
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
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVAudioEngineConfigurationChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
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
