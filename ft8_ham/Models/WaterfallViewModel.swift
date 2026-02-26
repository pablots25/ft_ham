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

@MainActor
final class WaterfallViewModel: ObservableObject {

    // MARK: - FFT Properties
    private var fft: RealtimeFFT?
    private lazy var magsBuffer: [Float] = [Float](repeating: 0, count: config.waterfallFFTSize / 2)

    // MARK: - Background handling
    private var isInBackground: Bool = false
    private var showBlackWhenBackgrounded: Bool = true

    /// New helper to handle FFT and update in one step
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
        var targetFPS: Double = 30.0
        var maxDisplayFrequency: Float = 800.0

        static let absoluteMaxRows = 2000
    }

    @Published var waterfallImage: Image? = nil
    @Published var visibleRows: Int = 0

    // Overlay flags
    @Published var showOverlay: Bool = true
    @Published var showTimestamps: Bool = true
    @Published var showVerticalLabels: Bool = true
    @Published var showFrequencyTicks: Bool = true
    @Published var showFrequencyMarker: Bool = true

    // Overlay data
    @Published var timestampItems: [TimestampOverlay] = []
    @Published var verticalLabels: [VerticalLabelOverlay] = []

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

            for x in 0 ..< w {
                let binIndex = Int(Float(x) / Float(w) * Float(maxBin)).clamped(to: 0 ... (maxBin - 1))
                let mag = mags[binIndex]
                waterfallBufferFlat[writeIndex + x] = mag

                let db = 20 * log10(max(mag, 1e-12))
                let scaled = ((db - config.waterfallMinDB) / (config.waterfallMaxDB - config.waterfallMinDB))
                    .clamped(to: 0 ... 1)
                let t = sqrt(scaled)
                let idx = Int((t * 255).rounded()).clamped(to: 0 ... 255)
                pixelData[row * w + x] = waterfallPalette[idx]
            }
        }

        // Timestamp logic ALWAYS runs
        let now = Date()
        if now >= nextUTCMark {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(abbreviation: "UTC")
            formatter.dateFormat = "HH:mm:ss"
            timestampRows[absoluteRowCounter] = formatter.string(from: nextUTCMark)
            nextUTCMark = nextUTCMark.addingTimeInterval(config.timestampInterval)
        }

        writeIndex = (writeIndex + w) % waterfallBufferFlat.count
        absoluteRowCounter += 1

        // Remove old timestamps and labels beyond visible rows
        let cutoff = absoluteRowCounter - max(1, visibleRows)
        timestampRows = timestampRows.filter { $0.key >= cutoff }
        verticalLabelRows = verticalLabelRows.filter { $0.key >= cutoff }

        // Update overlay arrays independently of view
        updateOverlayPositions()

        if visibleRows > 0 { renderWaterfallIncremental() }
    }

    @MainActor
    private func renderWaterfallIncremental() {
        guard frameLimiter.shouldRender(), let ctx = context, let rawPtr = ctx.data else { return }
        
        let w = width
        let h = max(1, min(visibleRows, height))
        let pixelData = rawPtr.assumingMemoryBound(to: UInt32.self)
        
        var visiblePixels = [UInt32](repeating: 0, count: w * h)
        let currentWriteRow = writeIndex / w
        
        for y in 0 ..< h {
            let srcRow = (currentWriteRow - h + y + height) % height
            let dstBase = (h - y - 1) * w
            let srcBase = srcRow * w
            for x in 0 ..< w {
                visiblePixels[dstBase + x] = pixelData[srcBase + x]
            }
        }
        
        if let cg = makeCGImageFromARGB(pixelData: visiblePixels, width: w, height: h) {
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
    
    
    private func makeCGImageFromARGB(pixelData: [UInt32], width: Int, height: Int) -> CGImage? {
        guard pixelData.count == width * height else { return nil }
        let bytesPerRow = width * 4
        
        return pixelData.withUnsafeBytes { rawBuffer -> CGImage? in
            guard let provider = CGDataProvider(data: Data(
                bytes: rawBuffer.baseAddress!,
                count: rawBuffer.count
            ) as CFData) else { return nil }
            
            let bitmapInfo = CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue
            )
            
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

