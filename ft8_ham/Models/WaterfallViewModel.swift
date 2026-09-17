//
//  WaterfallViewModel.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/11/25.
//

import Accelerate
import SwiftUI
import UIKit

struct TimestampOverlay: Equatable {
    let text: String
    var row: Int
}

struct VerticalLabelOverlay: Equatable {
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
    // Cached per-pixel bin-index map — recomputed only when the pixel width,
    // the FFT size or the sample rate changes
    private var cachedBinIndices: [Int] = []
    private var cachedBinMapKey: BinMapKey?
    /// Smoothed per-bin noise floor in dBFS for auto-ranging. `nil` until the
    /// first rendered row seeds it.
    private var smoothedFloorDB: Float?
    private var scratchSort: [Float] = []   // scratch copy for the percentile

    // Background FFT helper — not actor-isolated, safe to call from any queue
    private let backgroundFFT = BackgroundFFTProcessor()

    // MARK: - Background handling
    private var isInBackground: Bool = false
    private var showBlackWhenBackgrounded: Bool = true

    /// Called from a background audio queue. Runs the FFT there, then dispatches
    /// only the lightweight magnitude array to @MainActor for the pixel-write step.
    /// This keeps vDSP_fft_zip off the main thread entirely.
    /// - Parameter sampleRate: the rate of `samples`. The frequency axis is
    ///   derived from it, so it must be the real capture rate (the microphone
    ///   runs at the hardware rate, not at the 12 kHz decode/playback rate).
    nonisolated func updateWaterfallFromSamplesAsync(_ samples: [Float], sampleRate: Double? = nil) {
        guard !samples.isEmpty else { return }
        let mags = backgroundFFT.computeMagnitudes(from: samples)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let sampleRate, sampleRate > 0, self.sampleRate != Float(sampleRate) {
                self.sampleRate = Float(sampleRate)
            }
            self.updateWaterfall(from: mags)
        }
    }

    // MARK: - Visibility

    /// Views currently showing this waterfall, with the rows each one needs.
    /// Rendering (CGImage creation + publish) only happens while at least one
    /// view is on screen; the pixel buffer keeps scrolling regardless so the
    /// history is right when a view comes back.
    private var viewerRows: [UUID: Int] = [:]

    func viewerAppeared(_ id: UUID, rows: Int) {
        viewerRows[id] = max(1, rows)
        recomputeVisibleRows()
    }

    func viewerDisappeared(_ id: UUID) {
        viewerRows[id] = nil
        recomputeVisibleRows()
    }

    private func recomputeVisibleRows() {
        let rows = viewerRows.values.max() ?? 0
        if visibleRows != rows { visibleRows = rows }
        if rows > 0 { ensureBufferCanHold(visibleRows: rows) }
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
        /// Colour window in dBFS, used only when `waterfallAutoRange` is off.
        /// A -20 dBFS noise floor sits around -47 dBFS per bin after the Hann
        /// window, so this shows the floor near the bottom of the palette.
        var waterfallMinDB: Float = -80.0
        var waterfallMaxDB: Float = -20.0
        /// Track the noise floor and slide the colour window with it. The
        /// built-in mic and a line-level sound card differ by tens of dB, and
        /// no single fixed window reads well on both: one saturates solid red
        /// while the other is all blue.
        var waterfallAutoRange: Bool = true
        /// With auto-range on, colour starts this far below the tracked floor
        /// (so the floor itself reads as the faint bottom of the palette)…
        var waterfallFloorMarginDB: Float = 6.0
        /// …and saturates this far above that.
        var waterfallSpanDB: Float = 45.0
        var timestampInterval: TimeInterval
        var targetFPS: Double = 15.0  // Reduced from 30 to 15 Hz for CPU optimization
        /// Audio frequency at the right edge of the waterfall, in Hz. The
        /// pixel rows, the overlay, the cursor and the tap-to-set-frequency
        /// mapping all derive from this one value, so they cannot drift apart.
        var maxDisplayFrequency: Float = 3200.0

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
    
    func xPosition(for frequency: Double, in width: CGFloat) -> CGFloat {
        CGFloat(frequency / Double(config.maxDisplayFrequency)) * width
    }

    /// Identifies one pixel → FFT-bin mapping; the map is rebuilt when any
    /// of these change.
    private struct BinMapKey: Equatable {
        let pixelWidth: Int
        let magsCount: Int
        let sampleRate: Float
        let maxDisplayFrequency: Float
    }

    /// For each of `pixelWidth` columns, the index into an FFT magnitude array
    /// of `magsCount` bins (covering 0 Hz … `sampleRate / 2`) whose bin is
    /// shown there, so that the columns span 0 Hz … `maxDisplayFrequency`.
    ///
    /// The bin width is taken from `magsCount`, not from the configured FFT
    /// size: the background FFT sizes itself to the audio buffer it gets, so
    /// the two can differ. If the requested span exceeds Nyquist the map
    /// stops at the last real bin.
    static func displayedBinIndices(
        pixelWidth: Int,
        magsCount: Int,
        sampleRate: Float,
        maxDisplayFrequency: Float
    ) -> [Int] {
        guard pixelWidth > 0, magsCount > 0, sampleRate > 0 else { return [] }
        let binHz = sampleRate / (2 * Float(magsCount))
        let maxBin = min(max(Int((maxDisplayFrequency / binHz).rounded()), 1), magsCount)
        return (0 ..< pixelWidth).map {
            min(Int(Float($0) / Float(pixelWidth) * Float(maxBin)), maxBin - 1)
        }
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
            guard mags.count > 1 else { return }

            // Resize scratch buffers only when width changes (once per session)
            if scratchMags.count != w {
                scratchMags = [Float](repeating: 0, count: w)
                scratchDB   = [Float](repeating: 0, count: w)
            }

            // Rebuild bin-index table only when the mapping changes
            let mapKey = BinMapKey(
                pixelWidth: w,
                magsCount: mags.count,
                sampleRate: sampleRate,
                maxDisplayFrequency: config.maxDisplayFrequency
            )
            if cachedBinMapKey != mapKey {
                cachedBinMapKey = mapKey
                cachedBinIndices = Self.displayedBinIndices(
                    pixelWidth: w,
                    magsCount: mags.count,
                    sampleRate: sampleRate,
                    maxDisplayFrequency: config.maxDisplayFrequency
                )
            }
            guard cachedBinIndices.count == w else { return }

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

            // 4. Pick the colour window: fixed, or tracking the noise floor
            let minDB: Float
            let maxDB: Float
            if config.waterfallAutoRange {
                let floor = trackNoiseFloor(rowDB: scratchDB, count: w)
                minDB = floor - config.waterfallFloorMarginDB
                maxDB = minDB + config.waterfallSpanDB
            } else {
                minDB = config.waterfallMinDB
                maxDB = config.waterfallMaxDB
            }

            // 5. Linear scale: (db − minDB) / (maxDB − minDB)  [in-place: D = A*a + b]
            let range = maxDB - minDB
            guard range != 0 else {
                // degenerate config — write black row and bail
                let rowOffset = row * w
                for x in 0 ..< w { pixelData[rowOffset + x] = 0xFF000000 }
                return
            }
            var scaleA: Float =  1.0 / range
            var scaleB: Float = -minDB / range
            vDSP_vsmsa(scratchDB, 1, &scaleA, &scaleB, &scratchDB, 1, vLen)

            // 6. Clamp to [0, 1]
            var clampLo: Float = 0.0, clampHi: Float = 1.0
            vDSP_vclip(scratchDB, 1, &clampLo, &clampHi, &scratchDB, 1, vLen)

            // 7. Square root
            vvsqrtf(&scratchDB, scratchDB, &wInt)

            // 8. Scale to [0, 255]
            var scale255: Float = 255.0
            vDSP_vsmul(scratchDB, 1, &scale255, &scratchDB, 1, vLen)

            // 9. Palette lookup — unavoidably scalar, but L1-cache-friendly (256-entry table)
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

        // Prune timestamps/labels that scrolled out of the (maximum) visible
        // range. Done every 64 rows rather than on every audio buffer: the
        // overlay accessors already clip to the visible height, so pruning is
        // only about keeping the dictionaries small.
        if absoluteRowCounter % 64 == 0 {
            let cutoff = absoluteRowCounter - Config.absoluteMaxRows
            timestampRows = timestampRows.filter { $0.key >= cutoff }
            verticalLabelRows = verticalLabelRows.filter { $0.key >= cutoff }
        }

        // Render (CGImage + publish) only while a view is on screen.
        if visibleRows > 0 { renderWaterfallIncremental() }
    }

    @MainActor
    /// Estimates the noise floor of one row as its median bin level, then
    /// smooths it over time so the palette does not pump with every FT8 slot.
    ///
    /// The median rather than a lower percentile: a line-level feed from a
    /// radio is near-silent outside the rig's passband (below ~300 Hz and
    /// above ~2.7 kHz), which can be a quarter or more of the displayed bins.
    /// A 30th percentile lands in that silence, drags the floor down by tens
    /// of dB and paints every real bin solid red. The median tolerates up to
    /// half the bins being silent, and FT8 signals rarely fill more than a
    /// third of the band, so it still sits on the noise.
    private func trackNoiseFloor(rowDB: [Float], count: Int) -> Float {
        if scratchSort.count != count {
            scratchSort = [Float](repeating: 0, count: count)
        }
        for i in 0 ..< count { scratchSort[i] = rowDB[i] }
        scratchSort.sort()
        let rowFloor = scratchSort[count / 2]

        guard let previous = smoothedFloorDB else {
            smoothedFloorDB = rowFloor
            return rowFloor
        }
        // Follow drops quickly (band went quiet / gain lowered) and rises
        // slowly, so a burst of strong signals does not lift the floor and
        // hide the weak ones underneath.
        let alpha: Float = rowFloor < previous ? 0.3 : 0.05
        let next = previous + alpha * (rowFloor - previous)
        smoothedFloorDB = next
        return next
    }

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
        return Double(x / width) * Double(config.maxDisplayFrequency)
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

