//
//  WaterfallViewModel.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/11/25.
//

import Accelerate
import SwiftUI
import UIKit

struct TimestampOverlay {
    let text: String
    var row: Int
}

struct VerticalLabelOverlay {
    let text: String
    var row: Int
    let frequency: Double
}

// MARK: - WaterfallOverlayState
// Holds only the overlay data that the Canvas needs. Keeping it in a separate
// ObservableObject means that `waterfallImage` changes (published by WaterfallViewModel)
// do NOT trigger a Canvas redraw — only actual overlay data changes do.
@MainActor
final class WaterfallOverlayState: ObservableObject {
    @Published var showOverlay: Bool = true
    @Published var showTimestamps: Bool = true
    @Published var showVerticalLabels: Bool = true
    @Published var showFrequencyTicks: Bool = true
    @Published var showFrequencyMarker: Bool = true
    @Published var timestampItems: [TimestampOverlay] = []
    @Published var verticalLabels: [VerticalLabelOverlay] = []
}

@MainActor
final class WaterfallViewModel: ObservableObject {

    // MARK: - FFT Properties
    private var fft: RealtimeFFT?
    private lazy var magsBuffer: [Float] = [Float](repeating: 0, count: config.waterfallFFTSize / 2)

    // Reused formatter — creating DateFormatter is expensive; keep one instance
    private let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // Pre-allocated render buffer — avoids ~3 MB heap allocation per render frame
    private var renderBuffer: [UInt32] = []

    // Scratch buffers for the vectorized pixel-color pipeline in updateWaterfall(from:)
    private var scratchMags: [Float] = []   // gathered bin magnitudes (width elements)
    private var scratchDB: [Float] = []     // reused through the vDSP/vForce chain
    // Cached per-pixel bin-index map — recomputed only when width or maxBin changes
    private var cachedBinIndices: [Int] = []
    private var cachedMaxBin: Int = -1

    // Background FFT helper — not actor-isolated, safe to call from any queue
    private let backgroundFFT = BackgroundFFTProcessor()

    // MARK: - Background handling
    private var isInBackground: Bool = false
    private var showBlackWhenBackgrounded: Bool = true

    /// Called from a background audio queue. Runs the FFT there, then dispatches
    /// only the lightweight magnitude array to @MainActor for the pixel-write step.
    /// This keeps vDSP_fft_zip off the main thread entirely.
    nonisolated func updateWaterfallFromSamplesAsync(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let mags = backgroundFFT.computeMagnitudes(from: samples)
        Task { @MainActor [weak self] in
            self?.updateWaterfall(from: mags)
        }
    }

    /// Legacy @MainActor path kept for backward compatibility.
    func updateWaterfallFromSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        if fft == nil {
            fft = RealtimeFFT(size: config.waterfallFFTSize)
        }

        let fftSize = config.waterfallFFTSize
        let count = min(samples.count, fftSize)
        let start = samples.count - count

        // We only use the last fftSize samples for the waterfall fft
        let fftInput = Array(samples[start..<samples.count])

        // Ensure our shared magsBuffer is the right size
        if magsBuffer.count != fftSize / 2 {
            magsBuffer = [Float](repeating: 0, count: fftSize / 2)
        }

        if isInBackground {
            // We still advance the waterfall, but with black rows
            updateWaterfall(from: magsBuffer)
        } else {
            _ = fft?.magnitudesDirect(fftInput, output: &magsBuffer)
            updateWaterfall(from: magsBuffer)
        }
    }

    enum Mode {
        case ft8
        case ft4

        var timestampInterval: TimeInterval {
            switch self {
            case .ft8: return 15.0
            case .ft4: return 7.5
            }
        }
    }

    @Published var mode: Mode {
        didSet {
            config.timestampInterval = mode.timestampInterval
            nextUTCMark = WaterfallViewModel.computeNextUTCAligned(interval: config.timestampInterval)
        }
    }

    struct Config {
        var waterfallFFTSize: Int
        var waterfallMaxRows: Int
        var waterfallMinDB: Float = -25.0
        var waterfallMaxDB: Float = 0.0
        var timestampInterval: TimeInterval
        var targetFPS: Double = 15.0  // Reduced from 30 to 15 Hz for CPU optimization
        var maxDisplayFrequency: Float = 800.0

        static let absoluteMaxRows = 2000
    }

    @Published var waterfallImage: Image? = nil
    @Published var visibleRows: Int = 0

    // Dedicated object for overlay state — decoupled from waterfallImage so the
    // Canvas in WaterfallOverlayView only invalidates when overlay data changes.
    let overlayState = WaterfallOverlayState()

    // Overlay flags — forwarded to overlayState for backward-compatible access
    var showOverlay: Bool {
        get { overlayState.showOverlay }
        set { overlayState.showOverlay = newValue }
    }
    var showTimestamps: Bool {
        get { overlayState.showTimestamps }
        set { overlayState.showTimestamps = newValue }
    }
    var showVerticalLabels: Bool {
        get { overlayState.showVerticalLabels }
        set { overlayState.showVerticalLabels = newValue }
    }
    var showFrequencyTicks: Bool {
        get { overlayState.showFrequencyTicks }
        set { overlayState.showFrequencyTicks = newValue }
    }
    var showFrequencyMarker: Bool {
        get { overlayState.showFrequencyMarker }
        set { overlayState.showFrequencyMarker = newValue }
    }

    // Overlay data — forwarded to overlayState
    var timestampItems: [TimestampOverlay] {
        get { overlayState.timestampItems }
        set { overlayState.timestampItems = newValue }
    }
    var verticalLabels: [VerticalLabelOverlay] {
        get { overlayState.verticalLabels }
        set { overlayState.verticalLabels = newValue }
    }

    private var timestampRows: [Int: String] = [:]
    private var verticalLabelRows: [Int: [(text: String, frequency: Double)]] = [:]
    private var nextUTCMark: Date = .init()
    private var absoluteRowCounter: Int = 0

    private let wfLogger = AppLogger(category: "WF")
    var config: Config

    var width: Int { config.waterfallFFTSize / 2 }
    var height: Int { config.waterfallMaxRows }

    private var waterfallBufferFlat: [Float]
    private var writeIndex: Int

    // Use same sample rate as AudioManager
    var sampleRate: Float

    private lazy var waterfallPalette: [UInt32] = (0 ... 255).map { i -> UInt32 in
        let t = Float(i) / 255.0
        let r: UInt8
        let g: UInt8
        let b: UInt8

        switch t {
        case 0.0 ..< 0.25:
            let f = t / 0.25
            r = 0
            g = UInt8(255 * f)
            b = 255
        case 0.25 ..< 0.5:
            let f = (t - 0.25) / 0.25
            r = UInt8(255 * f)
            g = 255
            b = UInt8(255 * (1.0 - f))
        case 0.5 ..< 0.75:
            let f = (t - 0.5) / 0.25
            r = 255
            g = UInt8(255 * (1.0 - 0.5 * f))
            b = 0
        default:
            let f = (t - 0.75) / 0.25
            r = 255
            g = UInt8(127 * (1.0 - f))
            b = 0
        }

        return (255 << 24) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }

    private var context: CGContext?
    private var frameLimiter: FrameLimiter

    init(sampleRate: Float, waterfallFFTSize: Int, waterfallRows: Int, isFT4: Bool) {
        let initialMode: Mode = isFT4 ? .ft4 : .ft8
        self.mode = initialMode

        // Initialize config with the right timestamp interval
        self.config = Config(
            waterfallFFTSize: waterfallFFTSize,
            waterfallMaxRows: waterfallRows,
            timestampInterval: initialMode.timestampInterval
        )

        self.sampleRate = sampleRate
        frameLimiter = FrameLimiter(targetFPS: config.targetFPS)

        let w = max(2, config.waterfallFFTSize) / 2
        let h = max(1, config.waterfallMaxRows)

        waterfallBufferFlat = [Float](repeating: 0, count: w * h)
        writeIndex = 0

        setupContext(width: w, height: h)
        wfLogger.log(.info, "WaterfallViewModel initialized: FFTSize \(w * 2), rows \(h)")

        nextUTCMark = WaterfallViewModel.computeNextUTCAligned(interval: config.timestampInterval)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - App lifecycle handlers

    @objc
    private func handleDidEnterBackground() {
        wfLogger.log(.info, "App entered background, writing black rows")
        isInBackground = true
    }

    @objc
    private func handleWillEnterForeground() {
        wfLogger.log(.info, "App entered foreground, resuming waterfall")
        isInBackground = false

        nextUTCMark = WaterfallViewModel.computeNextUTCAligned(interval: config.timestampInterval)
    }


    // Compute next aligned UTC timestamp (e.g. next :00, :15, :30, :45)
    private static func computeNextUTCAligned(interval: TimeInterval) -> Date {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let comp = cal.dateComponents(in: TimeZone(abbreviation: "UTC")!, from: now)
        let s = comp.second ?? 0
        let remainder = Double(s).truncatingRemainder(dividingBy: interval)
        return now.addingTimeInterval(interval - remainder)
    }
    
    private func setupContext(width w: Int, height h: Int) {
        context = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
    
    func ensureBufferCanHold(visibleRows: Int) {
        let w = width
        // Limit rows to absolute maximum
        let cappedRows = min(max(visibleRows, height), Config.absoluteMaxRows)
        guard cappedRows > height else { return }
        
        let oldBuffer = waterfallBufferFlat
        waterfallBufferFlat = [Float](repeating: 0, count: cappedRows * w)
        for i in 0 ..< height {
            waterfallBufferFlat[(cappedRows - height + i) * w ..< (cappedRows - height + i + 1) * w] =
            oldBuffer[i * w ..< (i + 1) * w]
        }
        writeIndex = (cappedRows - height) * w
        config.waterfallMaxRows = cappedRows
        setupContext(width: w, height: cappedRows)
    }
    
    // ---------------------------------------------------------
    // Overlay helpers
    // ---------------------------------------------------------
    func addVerticalLabel(text: String, frequency: Double) {
        verticalLabelRows[absoluteRowCounter, default: []].append((text: text, frequency: frequency))
    }
    
    func addVerticalLabels(_ labels: [(String, Double)]) {
        guard !labels.isEmpty else { return }
        verticalLabelRows[absoluteRowCounter, default: []].append(contentsOf: labels)
    }
    
    @MainActor
    func updateOverlayPositions() {
        guard showOverlay else { return }
        
        // Shift rows down
        if showTimestamps {
            timestampItems = timestampItems.map { TimestampOverlay(text: $0.text, row: $0.row + 1) }
        }
        if showVerticalLabels {
            verticalLabels = verticalLabels.map { VerticalLabelOverlay(text: $0.text, row: $0.row + 1, frequency: $0.frequency) }
        }
        
        // Remove old rows
        let maxRows = max(1, visibleRows)
        if showTimestamps {
            timestampItems = timestampItems.filter { $0.row < maxRows }
        }
        if showVerticalLabels {
            verticalLabels = verticalLabels.filter { $0.row < maxRows }
        }
        
        // Add new overlays for current row
        if showTimestamps, let ts = timestampRows[absoluteRowCounter] {
            timestampItems.append(TimestampOverlay(text: ts, row: 0))
        }
        if showVerticalLabels, let labels = verticalLabelRows[absoluteRowCounter] {
            for label in labels {
                verticalLabels.append(VerticalLabelOverlay(text: label.text, row: 0, frequency: label.frequency))
            }
        }
    }
    
    func xPosition(for frequency: Double, in width: CGFloat) -> CGFloat {
        let maxFreq = Double(config.maxDisplayFrequency) * 4.0
        return CGFloat(frequency / maxFreq) * width
    }

    // ---------------------------------------------------------
    // Waterfall update
    // ---------------------------------------------------------
    func updateWaterfall(from mags: [Float]) {
        let w = width
        guard let ctx = context, let rawPtr = ctx.data else { return }

        let row = writeIndex / w
        let pixelData = rawPtr.assumingMemoryBound(to: UInt32.self)

        if isInBackground && showBlackWhenBackgrounded {
            // Write a full black row
            for x in 0 ..< w {
                waterfallBufferFlat[writeIndex + x] = 0
                pixelData[row * w + x] = 0xFF000000
            }
        } else {
            guard mags.count >= w else { return }

            let nyquist = max(1.0, sampleRate / 2.0)
            let maxBin = min(max(Int(round((config.maxDisplayFrequency / nyquist) * Float(w))), 1), w)

            // Resize scratch buffers only when width changes (once per session)
            if scratchMags.count != w {
                scratchMags = [Float](repeating: 0, count: w)
                scratchDB   = [Float](repeating: 0, count: w)
            }

            // Rebuild bin-index table only when the mapping changes
            if cachedBinIndices.count != w || cachedMaxBin != maxBin {
                cachedMaxBin = maxBin
                cachedBinIndices = (0 ..< w).map {
                    min(Int(Float($0) / Float(w) * Float(maxBin)), maxBin - 1)
                }
            }

            // Gather magnitudes: mags[binIndex] → scratchMags
            // Also write raw mags into the float waterfall buffer (unchanged semantics)
            let rowBase = writeIndex
            for x in 0 ..< w {
                let mag = mags[cachedBinIndices[x]]
                scratchMags[x] = mag
                waterfallBufferFlat[rowBase + x] = mag
            }

            // --- Vectorized dB + scale + sqrt pipeline (vDSP / vForce) ---
            var wInt = Int32(w)
            var vLen = vDSP_Length(w)

            // 1. Clamp to avoid log10(0): max(mag, 1e-12)
            var logFloor: Float = 1e-12
            var logCeil:  Float = .greatestFiniteMagnitude
            vDSP_vclip(scratchMags, 1, &logFloor, &logCeil, &scratchDB, 1, vLen)

            // 2. log10 (vectorized vForce)
            vvlog10f(&scratchDB, scratchDB, &wInt)

            // 3. ×20 → dB
            var factor20: Float = 20.0
            vDSP_vsmul(scratchDB, 1, &factor20, &scratchDB, 1, vLen)

            // 4. Linear scale: (db − minDB) / (maxDB − minDB)  [in-place: D = A*a + b]
            let range = config.waterfallMaxDB - config.waterfallMinDB
            guard range != 0 else {
                // degenerate config — write black row and bail
                let rowOffset = row * w
                for x in 0 ..< w { pixelData[rowOffset + x] = 0xFF000000 }
                return
            }
            var scaleA: Float =  1.0 / range
            var scaleB: Float = -config.waterfallMinDB / range
            vDSP_vsmsa(scratchDB, 1, &scaleA, &scaleB, &scratchDB, 1, vLen)

            // 5. Clamp to [0, 1]
            var clampLo: Float = 0.0, clampHi: Float = 1.0
            vDSP_vclip(scratchDB, 1, &clampLo, &clampHi, &scratchDB, 1, vLen)

            // 6. Square root
            vvsqrtf(&scratchDB, scratchDB, &wInt)

            // 7. Scale to [0, 255]
            var scale255: Float = 255.0
            vDSP_vsmul(scratchDB, 1, &scale255, &scratchDB, 1, vLen)

            // 8. Palette lookup — unavoidably scalar, but L1-cache-friendly (256-entry table)
            let rowOffset = row * w
            for x in 0 ..< w {
                let idx = Int(scratchDB[x]).clamped(to: 0 ... 255)
                pixelData[rowOffset + x] = waterfallPalette[idx]
            }
        }

        // Timestamp logic ALWAYS runs — uses cached formatter (avoids per-call allocation)
        let now = Date()
        if now >= nextUTCMark {
            timestampRows[absoluteRowCounter] = utcFormatter.string(from: nextUTCMark)
            nextUTCMark = nextUTCMark.addingTimeInterval(config.timestampInterval)
        }

        writeIndex = (writeIndex + w) % waterfallBufferFlat.count
        absoluteRowCounter += 1

        // Remove old timestamps and labels beyond visible rows
        let cutoff = absoluteRowCounter - max(1, visibleRows)
        timestampRows = timestampRows.filter { $0.key >= cutoff }
        verticalLabelRows = verticalLabelRows.filter { $0.key >= cutoff }

        // Overlay publishing is gated inside renderWaterfallIncremental so that
        // @Published arrays are only mutated at render-rate (≤15 FPS) rather than
        // at the audio-callback rate (~24 Hz), preventing spurious Canvas redraws.
        if visibleRows > 0 { renderWaterfallIncremental() }
    }

    @MainActor
    private func renderWaterfallIncremental() {
        guard frameLimiter.shouldRender(), let ctx = context, let rawPtr = ctx.data else { return }

        let w = width
        let h = max(1, min(visibleRows, height))
        let pixelData = rawPtr.assumingMemoryBound(to: UInt32.self)

        // Reuse pre-allocated render buffer; only resize when dimensions change
        let needed = w * h
        if renderBuffer.count != needed {
            renderBuffer = [UInt32](repeating: 0, count: needed)
        }

        let currentWriteRow = writeIndex / w
        for y in 0 ..< h {
            let srcRow = (currentWriteRow - h + y + height) % height
            let dstBase = (h - y - 1) * w
            let srcBase = srcRow * w
            renderBuffer.withUnsafeMutableBufferPointer { dst in
                let src = pixelData + srcBase
                (dst.baseAddress! + dstBase).assign(from: src, count: w)
            }
        }

        if let cg = makeCGImageFromARGB(pixelData: &renderBuffer, width: w, height: h) {
            waterfallImage = Image(uiImage: UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up))
        }

        // Call here so @Published overlay arrays are only mutated at render-rate (≤15 FPS)
        updateOverlayPositions()
    }
    // MARK: - Overlay toggles helpers
    
    /// Toggle the master "Show All Overlays"
    func setShowAllOverlays(_ value: Bool) {
        showOverlay = value
        showTimestamps = value
        showVerticalLabels = value
        showFrequencyTicks = value
        showFrequencyMarker = value
    }
    
    /// Toggle individual "Timestamps" overlay
    func setShowTimestamps(_ value: Bool) {
        showTimestamps = value
        showOverlay = showTimestamps || showVerticalLabels || showFrequencyTicks || showFrequencyMarker
    }
    
    /// Toggle individual "Vertical Labels" overlay
    func setShowVerticalLabels(_ value: Bool) {
        showVerticalLabels = value
        showOverlay = showTimestamps || showVerticalLabels || showFrequencyTicks || showFrequencyMarker
    }
    
    /// Toggle individual "Frequency Ticks" overlay
    func setShowFrequencyTicks(_ value: Bool) {
        showFrequencyTicks = value
        showOverlay = showTimestamps || showVerticalLabels || showFrequencyTicks || showFrequencyMarker
    }
    
    /// Toggle individual "Frequency Marker" overlay
    func setShowFrequencyMarker(_ value: Bool) {
        showFrequencyMarker = value
        showOverlay = showTimestamps || showVerticalLabels || showFrequencyTicks || showFrequencyMarker
    }
    
    /// Helper to toggle master overlay
    func toggleShowAllOverlays() {
        setShowAllOverlays(!showOverlay)
    }
    
    /// Toggle timestamps independently
    func toggleTimestamps() {
        setShowTimestamps(!showTimestamps)
    }
    
    /// Toggle vertical labels independently
    func toggleVerticalLabels() {
        setShowVerticalLabels(!showVerticalLabels)
    }
    
    /// Toggle frequency ticks independently
    func toggleFrequencyTicks() {
        setShowFrequencyTicks(!showFrequencyTicks)
    }
    
    /// Toggle frequency marker independently
    func toggleFrequencyMarker() {
        setShowFrequencyMarker(!showFrequencyMarker)
    }
    
    
    private func makeCGImageFromARGB(pixelData: inout [UInt32], width: Int, height: Int) -> CGImage? {
        guard pixelData.count == width * height else { return nil }
        let bytesPerRow = width * 4
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )
        // withUnsafeBytes gives a zero-copy view; CGDataProvider copies the bytes once into
        // the CGImage backing store — no intermediate Data allocation.
        return pixelData.withUnsafeBytes { rawBuffer -> CGImage? in
            guard
                let base = rawBuffer.baseAddress,
                let provider = CGDataProvider(data: CFDataCreate(nil, base.assumingMemoryBound(to: UInt8.self), rawBuffer.count))
            else { return nil }
            return CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
    }
    
    func updateConfig(_ update: (inout Config) -> Void) {
        var c = config
        update(&c)
        // Apply absolute max limit
        c.waterfallMaxRows = min(c.waterfallMaxRows, Config.absoluteMaxRows)
        config = c
        frameLimiter = FrameLimiter(targetFPS: config.targetFPS)
        ensureBufferCanHold(visibleRows: visibleRows)
        nextUTCMark = WaterfallViewModel.computeNextUTCAligned(interval: config.timestampInterval)
    }
    
    // MARK: - Overlay accessors
    
    func timestampsForOverlay(height: Int) -> [TimestampOverlay] {
        guard showOverlay && showTimestamps else { return [] }
        let topRow = absoluteRowCounter - 1
        return timestampRows.compactMap { absRow, text in
            let rowOffset = topRow - absRow
            return (rowOffset >= 0 && rowOffset < height) ? TimestampOverlay(text: text, row: rowOffset) : nil
        }
    }
    
    func verticalLabelsForOverlay(height: Int) -> [VerticalLabelOverlay] {
        guard showOverlay && showVerticalLabels else { return [] }
        let topRow = absoluteRowCounter - 1
        return verticalLabelRows.compactMap { absRow, labels -> [VerticalLabelOverlay]? in
            let rowOffset = topRow - absRow
            guard rowOffset >= 0 && rowOffset < height else { return nil }
            return labels.map { VerticalLabelOverlay(text: $0.text, row: rowOffset, frequency: $0.frequency) }
        }.flatMap { $0 }
    }
    
    func frequencyAtPixel(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * Double(config.maxDisplayFrequency) * 4.0
    }
    
    @MainActor
    func resyncNextTimestampFromNow() {
        let now = Date()
        let aligned = WaterfallViewModel.computeNextUTCAligned(interval: config.timestampInterval)
        nextUTCMark = aligned <= now ? aligned.addingTimeInterval(config.timestampInterval) : aligned
    }
    
}

// MARK: - BackgroundFFTProcessor
// A thread-safe, non-actor FFT helper that can be called from any queue.
// WaterfallViewModel holds one instance and calls computeMagnitudes() from
// the background audio queue so vDSP work stays off @MainActor.
private final class BackgroundFFTProcessor: @unchecked Sendable {
    private var fft: RealtimeFFT?
    private var magsBuffer: [Float] = []
    private let lock = NSLock()

    func computeMagnitudes(from samples: [Float]) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        // Lazily init FFT with the sample count as the FFT size (power-of-two)
        let fftSize = samples.count.previousPowerOfTwo
        if fft?.n != fftSize {
            fft = RealtimeFFT(size: fftSize)
            magsBuffer = [Float](repeating: 0, count: fftSize / 2)
        }
        guard let fft else { return [] }
        if magsBuffer.count != fftSize / 2 {
            magsBuffer = [Float](repeating: 0, count: fftSize / 2)
        }
        _ = samples.withUnsafeBufferPointer { ptr in
            fft.magnitudesDirect(ptr.baseAddress!, output: &magsBuffer)
        }
        return magsBuffer
    }
}

private extension Int {
    /// Largest power of two ≤ self (minimum 2)
    var previousPowerOfTwo: Int {
        guard self >= 2 else { return 2 }
        var n = self
        n |= (n >> 1); n |= (n >> 2); n |= (n >> 4); n |= (n >> 8); n |= (n >> 16)
        return n - (n >> 1)
    }
}

// MARK: - FrameLimiter

private struct FrameLimiter {
    private let minInterval: TimeInterval
    private var last: TimeInterval = 0

    init(targetFPS: Double) {
        minInterval = targetFPS > 0 ? 1.0 / targetFPS : 0
    }

    mutating func shouldRender(now: TimeInterval = CACurrentMediaTime()) -> Bool {
        guard minInterval > 0 else { return true }
        if now - last >= minInterval {
            last = now
            return true
        }
        return false
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

