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
// The overlay toggles, kept apart from the row data so flipping one only
// touches the layers it controls.
@MainActor
final class WaterfallOverlayState: ObservableObject {
    @Published var showOverlay: Bool = true
    @Published var showTimestamps: Bool = true
    @Published var showVerticalLabels: Bool = true
    @Published var showFrequencyTicks: Bool = true
    @Published var showFrequencyMarker: Bool = true
}

/// Receives the waterfall's pixel rows and overlay marks as they are
/// produced, on the main actor. Implemented by the on-screen renderer
/// (`WaterfallRenderView`); the view model keeps its own copy of the ring so
/// a sink attached later can be brought up to date with `reset`.
@MainActor
protocol WaterfallRenderSink: AnyObject {
    /// Replaces everything: the whole pixel ring (`height` rows of `width`
    /// BGRA pixels, row `writeRow` is the next to be written, so the newest
    /// row is `writeRow - 1`), and the overlay marks still in range.
    func reset(
        width: Int,
        height: Int,
        pixels: UnsafeBufferPointer<UInt32>,
        writeRow: Int,
        absoluteRow: Int,
        timestamps: [(absoluteRow: Int, text: String)],
        labels: [(absoluteRow: Int, text: String, frequency: Double)]
    )
    /// One new row, already coloured. `absoluteRow` counts rows since start.
    func append(row: UnsafeBufferPointer<UInt32>, ringRow: Int, absoluteRow: Int)
    func addTimestamp(_ text: String, absoluteRow: Int)
    func addLabels(_ labels: [(String, Double)], absoluteRow: Int)
}

/// Scrolling spectrogram fed by `FT8SlotMonitor`: one row per analysed
/// sub-block (80 ms for FT8), bins at the decoder's own resolution, so the
/// display shows exactly what the decoder sees.
///
/// Rows are pushed to attached `WaterfallRenderSink`s rather than published
/// as SwiftUI images: a new row costs the renderer a 4 KB texture upload and
/// one layer transform, not a pass through the SwiftUI view graph.
@MainActor
final class WaterfallViewModel: ObservableObject {

    // Reused formatter — creating DateFormatter is expensive; keep one instance
    private let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

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

    // MARK: - Render sinks

    private struct WeakSink {
        weak var sink: WaterfallRenderSink?
    }
    private var sinks: [WeakSink] = []

    /// Starts feeding `sink`, after handing it the history drawn so far.
    func attach(_ sink: WaterfallRenderSink) {
        sinks.removeAll { $0.sink == nil || $0.sink === sink }
        sinks.append(WeakSink(sink: sink))
        pixelRing.withUnsafeBufferPointer { pixels in
            sink.reset(
                width: width,
                height: height,
                pixels: pixels,
                writeRow: writeRow,
                absoluteRow: absoluteRowCounter,
                timestamps: timestampRows.map { (absoluteRow: $0.key, text: $0.value) },
                labels: verticalLabelRows.flatMap { row, labels in
                    labels.map { (absoluteRow: row, text: $0.text, frequency: $0.frequency) }
                }
            )
        }
    }

    func detach(_ sink: WaterfallRenderSink) {
        sinks.removeAll { $0.sink == nil || $0.sink === sink }
    }

    private func forEachSink(_ body: (WaterfallRenderSink) -> Void) {
        for entry in sinks {
            if let sink = entry.sink { body(sink) }
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
        /// Width of the pixel ring. Source bins are mapped onto these
        /// columns, so it does not have to match the monitor's bin count.
        var imageWidth: Int
        /// Rows kept in the ring; the display shows the newest ones that fit.
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
        /// Audio frequencies at the left and right edges of the waterfall, in
        /// Hz. The pixel rows, the overlay, the cursor and the
        /// tap-to-set-frequency mapping all derive from these two values, so
        /// they cannot drift apart. Defaults to the band the decoder analyses.
        var minDisplayFrequency: Float = 200.0
        var maxDisplayFrequency: Float = 3000.0

        static let absoluteMaxRows = 2000
    }

    /// Becomes true with the first row; the view shows a placeholder until then.
    @Published private(set) var hasData: Bool = false

    // Dedicated object for the overlay toggles.
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

    /// The coloured rows, `height` × `width` BGRA pixels, as a ring.
    private var pixelRing: [UInt32]
    /// Next row of the ring buffer to write (0 ..< height).
    private(set) var writeRow: Int = 0
    /// Rows produced since start; also the absolute index of the next row.
    var absoluteRowCount: Int { absoluteRowCounter }

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

    init(imageWidth: Int, waterfallRows: Int, isFT4: Bool) {
        let initialMode: Mode = isFT4 ? .ft4 : .ft8
        self.mode = initialMode

        // Initialize config with the right timestamp interval
        self.config = Config(
            imageWidth: max(2, imageWidth),
            waterfallMaxRows: min(max(1, waterfallRows), Config.absoluteMaxRows),
            timestampInterval: initialMode.timestampInterval
        )

        pixelRing = [UInt32](repeating: 0xFF000000, count: config.imageWidth * config.waterfallMaxRows)
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

    // ---------------------------------------------------------
    // Overlay helpers
    // ---------------------------------------------------------
    func addVerticalLabel(text: String, frequency: Double) {
        addVerticalLabels([(text, frequency)])
    }

    func addVerticalLabels(_ labels: [(String, Double)]) {
        guard !labels.isEmpty else { return }
        verticalLabelRows[absoluteRowCounter, default: []].append(contentsOf: labels)
        forEachSink { $0.addLabels(labels, absoluteRow: absoluteRowCounter) }
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

    /// Appends one monitor row (see `appendMonitorRow`) and hands it to the
    /// attached renderers.
    func updateWaterfall(monitorRow row: [UInt8], firstBinHz: Float, binHz: Float) {
        let w = width
        let rowOffset = writeRow * w

        if isInBackground && showBlackWhenBackgrounded {
            // Write a full black row
            for x in 0 ..< w { pixelRing[rowOffset + x] = 0xFF000000 }
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

            pixelRing.withUnsafeMutableBufferPointer { ring in
                paintRow(fromDB: &scratchDB, into: ring.baseAddress! + rowOffset)
            }
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
    /// overlay pruning, and pushing the row to the renderers.
    private func finishRow() {
        // Timestamp logic ALWAYS runs — uses cached formatter (avoids per-call allocation)
        let now = Date()
        if now >= nextUTCMark {
            let text = utcFormatter.string(from: nextUTCMark)
            timestampRows[absoluteRowCounter] = text
            forEachSink { $0.addTimestamp(text, absoluteRow: absoluteRowCounter) }
            nextUTCMark = nextUTCMark.addingTimeInterval(config.timestampInterval)
        }

        let w = width
        let ringRow = writeRow
        let absoluteRow = absoluteRowCounter
        pixelRing.withUnsafeBufferPointer { ring in
            let row = UnsafeBufferPointer(start: ring.baseAddress! + ringRow * w, count: w)
            forEachSink { $0.append(row: row, ringRow: ringRow, absoluteRow: absoluteRow) }
        }

        writeRow = (writeRow + 1) % height
        absoluteRowCounter += 1
        if !hasData { hasData = true }

        // Prune timestamps/labels that scrolled out of the (maximum) visible
        // range. Done every 64 rows rather than on every row: the overlay
        // accessors already clip to the visible height, so pruning is only
        // about keeping the dictionaries small.
        if absoluteRowCounter % 64 == 0 {
            let cutoff = absoluteRowCounter - height
            timestampRows = timestampRows.filter { $0.key >= cutoff }
            verticalLabelRows = verticalLabelRows.filter { $0.key >= cutoff }
        }
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


    /// Adjusts colour and axis settings. The ring's dimensions are fixed at
    /// init and are not affected.
    func updateConfig(_ update: (inout Config) -> Void) {
        var c = config
        update(&c)
        c.imageWidth = config.imageWidth
        c.waterfallMaxRows = config.waterfallMaxRows
        config = c
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

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
