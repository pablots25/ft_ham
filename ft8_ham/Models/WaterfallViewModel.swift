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
    let kind: WaterfallLabel.Kind
    let isWorked: Bool
    let spanRows: Int
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
        labels: [WaterfallPlacedLabel]
    )
    /// One new row, already coloured. `absoluteRow` counts rows since start.
    func append(row: UnsafeBufferPointer<UInt32>, ringRow: Int, absoluteRow: Int)
    func addTimestamp(_ text: String, absoluteRow: Int)
    /// Labels decoded together; the renderer lays the batch out so labels
    /// on neighbouring frequencies do not cover each other.
    func addLabels(_ labels: [WaterfallPlacedLabel])
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
    ///   - slotSequence: the monitor's slot counter for this row.
    ///   - slotRow: rows since that slot started.
    nonisolated func appendMonitorRow(
        _ row: UnsafeBufferPointer<UInt8>,
        firstBinHz: Float,
        binHz: Float,
        slotSequence: UInt,
        slotRow: Int
    ) {
        guard row.count > 1 else { return }
        let copy = Array(row)
        Task { @MainActor [weak self] in
            self?.updateWaterfall(
                monitorRow: copy, firstBinHz: firstBinHz, binHz: binHz,
                slotSequence: slotSequence, slotRow: slotRow
            )
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
                labels: placedLabels
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
        /// How rows are levelled and coloured; see `WaterfallDisplaySettings`.
        var display: WaterfallDisplaySettings = .init()
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
    private var placedLabels: [WaterfallPlacedLabel] = []
    private var nextUTCMark: Date = .init()
    private var absoluteRowCounter: Int = 0
    /// Absolute row at which each monitor slot started, by slot sequence.
    /// Filled as rows arrive; a decode looks its slot up here.
    private var slotStartRows: [UInt: Int] = [:]

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

    /// Baked colour table for `config.display.palette`.
    private var paletteLUT: [UInt32] = WaterfallPalette.default.lookupTable
    private var paletteLUTFor: WaterfallPalette = .default

    // Flatten scratch: per-column noise baseline (dB) and the row's envelope.
    private var baselineDB: [Float] = []
    private var envelopeDB: [Float] = []
    private var envelopeSmooth: [Float] = []
    /// Half-width in columns of the window the envelope is taken over:
    /// wide enough to step over an FT8 signal (50 Hz), narrow enough to
    /// follow the passband's shape.
    private var flattenHalfWindow: Int { max(4, Int(100.0 / Double(config.maxDisplayFrequency - config.minDisplayFrequency) * Double(width))) }

    init(imageWidth: Int, waterfallRows: Int, isFT4: Bool) {
        let initialMode: Mode = isFT4 ? .ft4 : .ft8
        self.mode = initialMode

        // Initialize config with the right timestamp interval
        self.config = Config(
            imageWidth: max(2, imageWidth),
            waterfallMaxRows: min(max(1, waterfallRows), Config.absoluteMaxRows),
            timestampInterval: initialMode.timestampInterval
        )

        config.display = WaterfallDisplaySettings.load()
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
        addLabels([WaterfallLabel(text: text, frequency: frequency)], slotSequence: nil, signalDuration: 0)
    }

    /// Places decoded messages on the waterfall.
    ///
    /// With the slot they were decoded from (`slotSequence`) and their DT,
    /// each label is anchored to the row its signal started on and spans
    /// the signal's duration; without that, it hangs from the current row.
    /// - Parameters:
    ///   - slotSequence: the monitor slot the decode came from.
    ///   - signalDuration: how long a transmission lasts (12.64 s FT8, 4.48 s FT4).
    func addLabels(_ labels: [WaterfallLabel], slotSequence: UInt?, signalDuration: Double) {
        guard !labels.isEmpty else { return }
        let slotStart = slotSequence.flatMap { slotStartRows[$0] }
        let placed = labels.map { label -> WaterfallPlacedLabel in
            if let slotStart, let dt = label.timeOffset, rowPeriod > 0 {
                let start = slotStart + Int((dt / rowPeriod).rounded())
                let span = max(1, Int((signalDuration / rowPeriod).rounded()))
                // The decode moment is the newest row we can show; a start
                // beyond it (bad DT) falls back to hanging from there.
                if start < absoluteRowCounter {
                    return WaterfallPlacedLabel(label: label, anchorRow: start, spanRows: min(span, absoluteRowCounter - start))
                }
            }
            return WaterfallPlacedLabel(label: label, anchorRow: absoluteRowCounter, spanRows: 0)
        }
        placedLabels.append(contentsOf: placed)
        forEachSink { $0.addLabels(placed) }
    }

    /// The label whose signal covers `frequency` (within `toleranceHz`) at
    /// `rowFromTop` rows below the newest row, if any — what a finger on the
    /// waterfall is pointing at. Prefers the closest frequency.
    func placedLabel(nearHz frequency: Double, rowFromTop: Int, toleranceHz: Double) -> WaterfallPlacedLabel? {
        let row = absoluteRowCounter - 1 - rowFromTop
        return placedLabels
            .filter { placed in
                abs(placed.label.frequency - frequency) <= toleranceHz &&
                    row >= placed.anchorRow - 2 &&
                    row <= placed.anchorRow + max(placed.spanRows, 40) + 2
            }
            .min { abs($0.label.frequency - frequency) < abs($1.label.frequency - frequency) }
    }

    /// The decoded signal closest to `frequency`, within `toleranceHz`, among
    /// the labels still on screen — used to snap a tap to a real station.
    func nearestLabelFrequency(to frequency: Double, toleranceHz: Double, withinRows: Int) -> Double? {
        let cutoff = absoluteRowCounter - withinRows
        return placedLabels
            .filter { $0.anchorRow + $0.spanRows >= cutoff && abs($0.label.frequency - frequency) <= toleranceHz }
            .min { abs($0.label.frequency - frequency) < abs($1.label.frequency - frequency) }?
            .label.frequency
    }

    /// Seconds per row: the monitor's `rowPeriod` (80 ms FT8, 24 ms FT4).
    /// Set by the owner whenever the monitor is (re)configured.
    var rowPeriod: Double = 0.08

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
    func updateWaterfall(
        monitorRow row: [UInt8],
        firstBinHz: Float,
        binHz: Float,
        slotSequence: UInt = 0,
        slotRow: Int = 0
    ) {
        let w = width
        let rowOffset = writeRow * w

        // Remember where this slot began, so decodes can be placed on it.
        if slotStartRows[slotSequence] == nil {
            slotStartRows[slotSequence] = absoluteRowCounter - slotRow
            if slotStartRows.count > 8 {
                let oldest = slotStartRows.keys.min()!
                slotStartRows[oldest] = nil
            }
        }

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
        let vLen = vDSP_Length(w)
        let display = config.display

        // 1. Flatten: subtract each column's own noise baseline so a shaped
        //    passband (line-in from a radio) reads level across the band.
        if display.flatten {
            flatten(&db)
        }

        // 2. Pick the colour window: tracking the noise floor, or fixed
        let minDB: Float
        if display.autoLevel {
            let floor = trackNoiseFloor(rowDB: db, count: w)
            minDB = floor - display.zeroDB
        } else {
            // Manual: `zeroDB` is the level (relative to the noise once
            // flattened, absolute otherwise) that maps to the bottom colour.
            minDB = display.manualFloorDB
        }
        let range = max(display.gainDB, 1)

        // 3. Linear scale to 0…255: (db − minDB) / range × 255  [D = A*a + b]
        var scaleA: Float = 255.0 / range
        var scaleB: Float = -minDB * 255.0 / range
        vDSP_vsmsa(db, 1, &scaleA, &scaleB, &db, 1, vLen)

        // 4. Clamp to [0, 255]
        var clampLo: Float = 0.0, clampHi: Float = 255.0
        vDSP_vclip(db, 1, &clampLo, &clampHi, &db, 1, vLen)

        // 5. Palette lookup — unavoidably scalar, but L1-cache-friendly (256-entry table)
        if paletteLUTFor != display.palette {
            paletteLUT = display.palette.lookupTable
            paletteLUTFor = display.palette
        }
        for x in 0 ..< w {
            pixels[x] = paletteLUT[Int(db[x])]
        }
    }

    /// Removes the passband's shape from one row, in place.
    ///
    /// The noise floor at each column is estimated as the minimum over a
    /// ±100 Hz window (an FT8 signal is 50 Hz wide, so the window always
    /// reaches noise beside it), smoothed across frequency and then over
    /// time, and subtracted. Noise ends up around 0 dB everywhere; signals
    /// keep their height above it.
    private func flatten(_ db: inout [Float]) {
        let w = width
        let r = flattenHalfWindow
        if envelopeDB.count != w {
            envelopeDB = [Float](repeating: 0, count: w)
            envelopeSmooth = [Float](repeating: 0, count: w)
            baselineDB = []
        }

        // Sliding minimum: O(w × window), a few hundred thousand compares
        // per row, well under a millisecond.
        db.withUnsafeBufferPointer { src in
            for x in 0 ..< w {
                var m = src[x]
                let lo = max(0, x - r), hi = min(w - 1, x + r)
                var i = lo
                while i <= hi {
                    if src[i] < m { m = src[i] }
                    i += 1
                }
                envelopeDB[x] = m
            }
        }
        // Smooth across frequency with a box of the same width (edges keep
        // the raw minimum), and lift by the expected min-to-median gap of
        // noise over that many samples so the result sits on the median.
        let box = 2 * r + 1
        if w > box {
            envelopeSmooth.withUnsafeMutableBufferPointer { dst in
                envelopeDB.withUnsafeBufferPointer { src in
                    vDSP_vswsum(src.baseAddress!, 1, dst.baseAddress! + r, 1, vDSP_Length(w - box + 1), vDSP_Length(box))
                    var inv = 1.0 / Float(box)
                    vDSP_vsmul(dst.baseAddress! + r, 1, &inv, dst.baseAddress! + r, 1, vDSP_Length(w - box + 1))
                    for x in 0 ..< r { dst[x] = src[x] }
                    for x in (w - r) ..< w { dst[x] = src[x] }
                }
            }
        } else {
            envelopeSmooth = envelopeDB
        }

        // Follow the envelope over time; slow enough not to flicker, fast
        // enough to track a gain change within a second or two.
        if baselineDB.count != w {
            baselineDB = envelopeSmooth
        } else {
            var alpha: Float = 0.1
            var oneMinus: Float = 0.9
            // baseline = 0.9·baseline + 0.1·envelope
            vDSP_vsmsma(baselineDB, 1, &oneMinus, envelopeSmooth, 1, &alpha, &baselineDB, 1, vDSP_Length(w))
        }
        vDSP_vsub(baselineDB, 1, db, 1, &db, 1, vDSP_Length(w))
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
            placedLabels.removeAll { $0.anchorRow + $0.spanRows < cutoff }
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


    /// One ring row's pixels, for tests.
    func pixelRowForTesting(ringRow: Int) -> [UInt32] {
        Array(pixelRing[(ringRow * width) ..< ((ringRow + 1) * width)])
    }

    /// The persisted display settings; writing saves them and applies them
    /// to the next row.
    var displaySettings: WaterfallDisplaySettings {
        get { config.display }
        set {
            guard newValue != config.display else { return }
            // Switching flatten on or off changes the scale the floor lives
            // in; start the trackers afresh rather than sliding from the old one.
            if newValue.flatten != config.display.flatten {
                baselineDB = []
                smoothedFloorDB = nil
            }
            config.display = newValue
            newValue.save()
        }
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
        return placedLabels.compactMap { placed in
            let rowOffset = topRow - placed.anchorRow
            guard rowOffset >= 0 && rowOffset < height else { return nil }
            return VerticalLabelOverlay(
                text: placed.label.text, row: rowOffset, frequency: placed.label.frequency,
                kind: placed.label.kind, isWorked: placed.label.isWorked, spanRows: placed.spanRows
            )
        }
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
