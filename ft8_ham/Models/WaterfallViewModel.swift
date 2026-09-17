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

/// Scrolling spectrogram fed by `FT8SlotMonitor`: one row per analysed
/// sub-block (80 ms for FT8), bins at the decoder's own resolution, so the
/// display shows exactly what the decoder sees.
@MainActor
final class WaterfallViewModel: ObservableObject {

    // Reused formatter — creating DateFormatter is expensive; keep one instance
    private let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // Pre-allocated render buffer — avoids ~3 MB heap allocation per render frame
    private var renderBuffer: [UInt32] = []

    // Scratch buffer for the vectorized pixel-color pipeline: gathered row
    // values in dB, reused through the vDSP/vForce chain
    private var scratchDB: [Float] = []
    // Cached per-pixel bin-index map — recomputed only when the pixel width,
    // the source bins or the displayed range change
    private var cachedBinIndices: [Int] = []
    private var cachedBinMapKey: BinMapKey?
    /// Smoothed noise floor in dB for auto-ranging. `nil` until the first
    /// rendered row seeds it.
    private var smoothedFloorDB: Float?
    private var scratchSort: [Float] = []   // scratch copy for the percentile

    // MARK: - Background handling
    private var isInBackground: Bool = false
    private var showBlackWhenBackgrounded: Bool = true

    // MARK: - Monitor input

    /// Called from the audio thread with one row from the slot monitor. Copies
    /// the row and hops to the main actor for the pixel-write step.
    /// - Parameters:
    ///   - row: magnitudes in increasing frequency order, 0–255 in 0.5 dB
    ///     steps with 0 = −120 dB (ft8_lib's waterfall encoding).
    ///   - firstBinHz: frequency of `row[0]`.
    ///   - binHz: spacing between consecutive values.
    nonisolated func appendMonitorRow(_ row: UnsafeBufferPointer<UInt8>, firstBinHz: Float, binHz: Float) {
        guard row.count > 1 else { return }
        let copy = Array(row)
        Task { @MainActor [weak self] in
            self?.updateWaterfall(monitorRow: copy, firstBinHz: firstBinHz, binHz: binHz)
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
        /// Width of the pixel image. Source bins are mapped onto these
        /// columns, so it does not have to match the monitor's bin count.
        var imageWidth: Int
        var waterfallMaxRows: Int
        /// Colour window in dB, used only when `waterfallAutoRange` is off.
        /// Rows arrive in ft8_lib's scale (0 dB ≈ a full-scale tone); a
        /// −20 dBFS noise floor spreads to roughly −50 dB per bin, so this
        /// shows that floor near the bottom of the palette.
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
        /// Audio frequencies at the left and right edges of the waterfall, in
        /// Hz. The pixel rows, the overlay, the cursor and the
        /// tap-to-set-frequency mapping all derive from these two values, so
        /// they cannot drift apart. Defaults to the band the decoder analyses.
        var minDisplayFrequency: Float = 200.0
        var maxDisplayFrequency: Float = 3000.0

        static let absoluteMaxRows = 2000
    }

    @Published var waterfallImage: Image? = nil
    /// Rows in the published `waterfallImage`. The view stretches the image
    /// to its own height, so the overlay needs this to place a row on screen.
    private(set) var renderedRows: Int = 0
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

    var width: Int { config.imageWidth }
    var height: Int { config.waterfallMaxRows }

    /// Next row of the ring buffer to write (0 ..< height).
    private var writeRow: Int = 0

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

    init(imageWidth: Int, waterfallRows: Int, isFT4: Bool) {
        let initialMode: Mode = isFT4 ? .ft4 : .ft8
        self.mode = initialMode

        // Initialize config with the right timestamp interval
        self.config = Config(
            imageWidth: max(2, imageWidth),
            waterfallMaxRows: max(1, waterfallRows),
            timestampInterval: initialMode.timestampInterval
        )

        frameLimiter = FrameLimiter(targetFPS: config.targetFPS)

        setupContext(width: width, height: height)
        wfLogger.log(.info, "WaterfallViewModel initialized: \(width) columns, \(height) rows")

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
        // CGContext does not promise zeroed memory; start from black.
        if let ctx = context, let raw = ctx.data {
            raw.assumingMemoryBound(to: UInt32.self).update(repeating: 0xFF000000, count: w * h)
        }
    }

    /// Grows the ring buffer so a view can show `visibleRows` rows, keeping
    /// the history already drawn.
    func ensureBufferCanHold(visibleRows: Int) {
        let w = width
        // Limit rows to absolute maximum
        let cappedRows = min(max(visibleRows, height), Config.absoluteMaxRows)
        guard cappedRows > height, let oldCtx = context, let oldRaw = oldCtx.data else { return }
        let oldHeight = height
        let oldPixels = oldRaw.assumingMemoryBound(to: UInt32.self)

        // Copy the old rows, oldest first, to the start of the new buffer so
        // the write position simply continues after them.
        var copied = [UInt32](repeating: 0xFF000000, count: cappedRows * w)
        for i in 0 ..< oldHeight {
            let srcRow = (writeRow + i) % oldHeight
            copied.withUnsafeMutableBufferPointer { dst in
                (dst.baseAddress! + i * w).update(from: oldPixels + srcRow * w, count: w)
            }
        }

        config.waterfallMaxRows = cappedRows
        setupContext(width: w, height: cappedRows)
        if let ctx = context, let raw = ctx.data {
            copied.withUnsafeBufferPointer { src in
                raw.assumingMemoryBound(to: UInt32.self).update(from: src.baseAddress!, count: copied.count)
            }
        }
        writeRow = oldHeight
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

    // ---------------------------------------------------------
    // Frequency axis
    // ---------------------------------------------------------

    /// Frequencies at the left and right edges of the display.
    var displayedFrequencyRange: ClosedRange<Double> {
        Double(config.minDisplayFrequency) ... Double(config.maxDisplayFrequency)
    }

    func xPosition(for frequency: Double, in width: CGFloat) -> CGFloat {
        let range = displayedFrequencyRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((frequency - range.lowerBound) / span) * width
    }

    func frequencyAtPixel(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let range = displayedFrequencyRange
        return range.lowerBound + Double(x / width) * (range.upperBound - range.lowerBound)
    }

    /// Bandwidth a transmission occupies above its base tone: 8 tones × 6.25 Hz
    /// for FT8, 4 tones × 20.83 Hz for FT4.
    static func occupiedBandwidthHz(isFT4: Bool) -> Double {
        isFT4 ? 83.3 : 50.0
    }

    /// Lowest and highest base tone the decoder can still see whole: it
    /// analyses 200–3000 Hz, so the top of the signal must stay under 3000.
    static func txFrequencyRange(isFT4: Bool) -> ClosedRange<Double> {
        200.0 ... (3000.0 - occupiedBandwidthHz(isFT4: isFT4))
    }

    /// Identifies one pixel → source-bin mapping; the map is rebuilt when any
    /// of these change.
    private struct BinMapKey: Equatable {
        let pixelWidth: Int
        let binCount: Int
        let firstBinHz: Float
        let binHz: Float
        let minDisplayHz: Float
        let maxDisplayHz: Float
    }

    /// For each of `pixelWidth` columns, the index of the source bin shown
    /// there, so that the columns span `minDisplayHz` … `maxDisplayHz`.
    /// Source bins are uniformly spaced: bin `i` is at `firstBinHz + i × binHz`.
    /// Columns outside the source band clamp to its edge bins.
    static func displayedBinIndices(
        pixelWidth: Int,
        binCount: Int,
        firstBinHz: Float,
        binHz: Float,
        minDisplayHz: Float,
        maxDisplayHz: Float
    ) -> [Int] {
        guard pixelWidth > 0, binCount > 0, binHz > 0, maxDisplayHz > minDisplayHz else { return [] }
        let spanHz = maxDisplayHz - minDisplayHz
        return (0 ..< pixelWidth).map { x in
            // Sample the centre of the column.
            let hz = minDisplayHz + (Float(x) + 0.5) / Float(pixelWidth) * spanHz
            let bin = Int(((hz - firstBinHz) / binHz).rounded())
            return bin.clamped(to: 0 ... (binCount - 1))
        }
    }

    // ---------------------------------------------------------
    // Waterfall update
    // ---------------------------------------------------------

    /// Appends one monitor row (see `appendMonitorRow`) and renders.
    func updateWaterfall(monitorRow row: [UInt8], firstBinHz: Float, binHz: Float) {
        let w = width
        guard let ctx = context, let rawPtr = ctx.data else { return }
        let pixelData = rawPtr.assumingMemoryBound(to: UInt32.self)
        let rowOffset = writeRow * w

        if isInBackground && showBlackWhenBackgrounded {
            // Write a full black row
            for x in 0 ..< w { pixelData[rowOffset + x] = 0xFF000000 }
        } else {
            guard row.count > 1 else { return }

            if scratchDB.count != w {
                scratchDB = [Float](repeating: 0, count: w)
            }

            // Rebuild bin-index table only when the mapping changes
            let mapKey = BinMapKey(
                pixelWidth: w,
                binCount: row.count,
                firstBinHz: firstBinHz,
                binHz: binHz,
                minDisplayHz: config.minDisplayFrequency,
                maxDisplayHz: config.maxDisplayFrequency
            )
            if cachedBinMapKey != mapKey {
                cachedBinMapKey = mapKey
                cachedBinIndices = Self.displayedBinIndices(
                    pixelWidth: w,
                    binCount: row.count,
                    firstBinHz: firstBinHz,
                    binHz: binHz,
                    minDisplayHz: config.minDisplayFrequency,
                    maxDisplayHz: config.maxDisplayFrequency
                )
            }
            guard cachedBinIndices.count == w else { return }

            // Gather the displayed bins, then decode ft8_lib's 8-bit scale:
            // dB = value / 2 − 120 (in-place: D = A*a + b)
            for x in 0 ..< w {
                scratchDB[x] = Float(row[cachedBinIndices[x]])
            }
            var toDBScale: Float = 0.5
            var toDBOffset: Float = -120.0
            vDSP_vsmsa(scratchDB, 1, &toDBScale, &toDBOffset, &scratchDB, 1, vDSP_Length(w))

            paintRow(fromDB: &scratchDB, into: pixelData + rowOffset)
        }

        finishRow()
    }

    /// Colours one row from per-column dB values and writes it to `pixels`.
    /// `db` is consumed as scratch space.
    private func paintRow(fromDB db: inout [Float], into pixels: UnsafeMutablePointer<UInt32>) {
        let w = width
        var wInt = Int32(w)
        let vLen = vDSP_Length(w)

        // 1. Pick the colour window: fixed, or tracking the noise floor
        let minDB: Float
        let maxDB: Float
        if config.waterfallAutoRange {
            let floor = trackNoiseFloor(rowDB: db, count: w)
            minDB = floor - config.waterfallFloorMarginDB
            maxDB = minDB + config.waterfallSpanDB
        } else {
            minDB = config.waterfallMinDB
            maxDB = config.waterfallMaxDB
        }

        // 2. Linear scale: (db − minDB) / (maxDB − minDB)  [in-place: D = A*a + b]
        let range = maxDB - minDB
        guard range != 0 else {
            // degenerate config — write black row and bail
            for x in 0 ..< w { pixels[x] = 0xFF000000 }
            return
        }
        var scaleA: Float =  1.0 / range
        var scaleB: Float = -minDB / range
        vDSP_vsmsa(db, 1, &scaleA, &scaleB, &db, 1, vLen)

        // 3. Clamp to [0, 1]
        var clampLo: Float = 0.0, clampHi: Float = 1.0
        vDSP_vclip(db, 1, &clampLo, &clampHi, &db, 1, vLen)

        // 4. Square root
        vvsqrtf(&db, db, &wInt)

        // 5. Scale to [0, 255]
        var scale255: Float = 255.0
        vDSP_vsmul(db, 1, &scale255, &db, 1, vLen)

        // 6. Palette lookup — unavoidably scalar, but L1-cache-friendly (256-entry table)
        for x in 0 ..< w {
            let idx = Int(db[x]).clamped(to: 0 ... 255)
            pixels[x] = waterfallPalette[idx]
        }
    }

    /// Bookkeeping shared by every row: slot timestamps, ring advance,
    /// overlay pruning and rendering.
    private func finishRow() {
        // Timestamp logic ALWAYS runs — uses cached formatter (avoids per-call allocation)
        let now = Date()
        if now >= nextUTCMark {
            timestampRows[absoluteRowCounter] = utcFormatter.string(from: nextUTCMark)
            nextUTCMark = nextUTCMark.addingTimeInterval(config.timestampInterval)
        }

        writeRow = (writeRow + 1) % height
        absoluteRowCounter += 1

        // Prune timestamps/labels that scrolled out of the (maximum) visible
        // range. Done every 64 rows rather than on every row: the overlay
        // accessors already clip to the visible height, so pruning is only
        // about keeping the dictionaries small.
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

        // Newest row at the top of the image.
        for y in 0 ..< h {
            let srcRow = (writeRow - h + y + height) % height
            let dstBase = (h - y - 1) * w
            let srcBase = srcRow * w
            renderBuffer.withUnsafeMutableBufferPointer { dst in
                let src = pixelData + srcBase
                (dst.baseAddress! + dstBase).update(from: src, count: w)
            }
        }

        if let cg = makeCGImageFromARGB(pixelData: &renderBuffer, width: w, height: h) {
            renderedRows = h
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
        // The pixel image is sized at init and only ever grows, through
        // ensureBufferCanHold, so the ring arithmetic always matches it.
        let requestedRows = c.waterfallMaxRows
        c.imageWidth = config.imageWidth
        c.waterfallMaxRows = config.waterfallMaxRows
        config = c
        frameLimiter = FrameLimiter(targetFPS: config.targetFPS)
        ensureBufferCanHold(visibleRows: max(visibleRows, requestedRows))
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

    @MainActor
    func resyncNextTimestampFromNow() {
        let now = Date()
        let aligned = WaterfallViewModel.computeNextUTCAligned(interval: config.timestampInterval)
        nextUTCMark = aligned <= now ? aligned.addingTimeInterval(config.timestampInterval) : aligned
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
