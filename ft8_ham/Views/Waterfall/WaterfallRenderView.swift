//
//  WaterfallRenderView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 21/9/26.
//

import MetalKit
import SwiftUI
import UIKit

// MARK: - Overlay style

/// What the overlay needs to know besides the rows: the frequency axis, the
/// TX marker and which parts are switched on. Plain values, compared before
/// any layer is rebuilt.
struct WaterfallOverlayStyle: Equatable {
    var minDisplayHz: Double
    var maxDisplayHz: Double
    var txFrequency: Double
    var isFT4: Bool
    var showOverlay: Bool
    var showTimestamps: Bool
    var showVerticalLabels: Bool
    var showFrequencyTicks: Bool
    var showFrequencyMarker: Bool
}

// MARK: - WaterfallRenderView

/// Draws the waterfall without going through SwiftUI for every row.
///
/// The pixel rows live in a Metal texture used as a ring; a new row is one
/// 4 KB `replace(region:)` and one redraw of a textured quad. The overlay is
/// Core Animation layers: timestamps and decoded-message labels are placed
/// once at their absolute row and the whole group is moved by a single
/// transform per row, while ticks and the TX marker are rebuilt only when
/// the style changes.
final class WaterfallRenderView: UIView, WaterfallRenderSink {

    // Points per waterfall row on screen.
    static let pointsPerRow: CGFloat = 1

    private let metalView = MTKView()
    private let renderer: WaterfallMetalRenderer?

    /// Ticks, tick labels, TX marker: depends on `style` and bounds only.
    private let staticLayer = CALayer()
    /// Timestamp lines and message labels, in absolute-row coordinates
    /// (y = −absoluteRow × pointsPerRow); shifted as rows arrive.
    private let scrollLayer = CALayer()
    private let timestampsLayer = CALayer()
    private let labelsLayer = CALayer()
    private let headerHeight: CGFloat = 15

    private var style: WaterfallOverlayStyle?
    private var ringHeight = 0
    private var topAbsoluteRow = -1   // absolute index of the newest row
    private var layoutSize: CGSize = .zero

    override init(frame: CGRect) {
        renderer = WaterfallMetalRenderer.make()
        super.init(frame: frame)
        isUserInteractionEnabled = false   // gestures belong to the SwiftUI host
        backgroundColor = .black

        metalView.device = renderer?.device
        metalView.delegate = renderer
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.framebufferOnly = true
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.isOpaque = true
        metalView.autoResizeDrawable = true
        addSubview(metalView)

        for l in [scrollLayer, timestampsLayer, labelsLayer, staticLayer] {
            l.contentsScale = UIScreen.main.scale
            l.masksToBounds = false
        }
        scrollLayer.addSublayer(timestampsLayer)
        scrollLayer.addSublayer(labelsLayer)
        layer.addSublayer(scrollLayer)
        layer.addSublayer(staticLayer)
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != layoutSize else { return }
        layoutSize = bounds.size
        metalView.frame = bounds
        renderer?.visibleRows = visibleRows
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        staticLayer.frame = bounds
        scrollLayer.frame = bounds
        rebuildStaticLayer()
        // Label geometry depends on the width; simplest to lay them out again.
        relayoutAllLabels()
        for sub in timestampsLayer.sublayers ?? [] { layoutTimestampLayer(sub) }
        updateScrollTransform()
        CATransaction.commit()
        metalView.setNeedsDisplay()
    }

    /// Rows that fit on screen at `pointsPerRow`, never more than the ring holds.
    private var visibleRows: Int {
        let fromHeight = Int((bounds.height / Self.pointsPerRow).rounded(.up))
        return max(1, ringHeight > 0 ? min(fromHeight, ringHeight) : fromHeight)
    }

    // MARK: Style

    func apply(style newStyle: WaterfallOverlayStyle) {
        guard newStyle != style else { return }
        let axisChanged = style.map {
            $0.minDisplayHz != newStyle.minDisplayHz || $0.maxDisplayHz != newStyle.maxDisplayHz
        } ?? true
        style = newStyle
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuildStaticLayer()
        scrollLayer.isHidden = !newStyle.showOverlay
        timestampsLayer.isHidden = !newStyle.showTimestamps
        labelsLayer.isHidden = !newStyle.showVerticalLabels
        if axisChanged { relayoutAllLabels() }
        CATransaction.commit()
    }

    private func x(forHz hz: Double) -> CGFloat {
        guard let style, style.maxDisplayHz > style.minDisplayHz else { return 0 }
        return CGFloat((hz - style.minDisplayHz) / (style.maxDisplayHz - style.minDisplayHz)) * bounds.width
    }

    // MARK: WaterfallRenderSink

    func reset(
        width: Int,
        height: Int,
        pixels: UnsafeBufferPointer<UInt32>,
        writeRow: Int,
        absoluteRow: Int,
        timestamps: [(absoluteRow: Int, text: String)],
        labels: [WaterfallPlacedLabel]
    ) {
        ringHeight = height
        topAbsoluteRow = absoluteRow - 1
        renderer?.reset(width: width, height: height, pixels: pixels, writeRow: writeRow)
        renderer?.visibleRows = visibleRows

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sub in timestampsLayer.sublayers ?? [] { sub.removeFromSuperlayer() }
        for t in timestamps { addTimestampLayer(t.text, absoluteRow: t.absoluteRow) }
        allLabels = labels
        relayoutAllLabels()
        updateScrollTransform()
        CATransaction.commit()
        metalView.setNeedsDisplay()
    }

    func append(row: UnsafeBufferPointer<UInt32>, ringRow: Int, absoluteRow: Int) {
        topAbsoluteRow = absoluteRow
        renderer?.append(row: row, ringRow: ringRow)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateScrollTransform()
        if absoluteRow % 64 == 0 { pruneScrolledOut() }
        CATransaction.commit()
        metalView.setNeedsDisplay()
    }

    func addTimestamp(_ text: String, absoluteRow: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addTimestampLayer(text, absoluteRow: absoluteRow)
        CATransaction.commit()
    }

    func addLabels(_ labels: [WaterfallPlacedLabel]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        allLabels.append(contentsOf: labels)
        layoutLabelBatch(labels)
        CATransaction.commit()
    }

    // MARK: Scrolling overlay

    /// Moves the absolute-row coordinate system so the newest row is at y = 0.
    private func updateScrollTransform() {
        let shift = CGFloat(topAbsoluteRow) * Self.pointsPerRow
        scrollLayer.sublayerTransform = CATransform3DMakeTranslation(0, shift, 0)
    }

    private func pruneScrolledOut() {
        let cutoff = topAbsoluteRow - ringHeight
        for sub in timestampsLayer.sublayers ?? [] where (sub.value(forKey: Self.absRowKey) as? Int ?? .max) < cutoff {
            sub.removeFromSuperlayer()
        }
        for sub in labelsLayer.sublayers ?? [] where (sub.value(forKey: Self.absRowKey) as? Int ?? .max) < cutoff {
            sub.removeFromSuperlayer()
        }
        allLabels.removeAll { $0.anchorRow + $0.spanRows < cutoff }
    }

    private static let absRowKey = "wf.absoluteRow"
    private static let textKey = "wf.text"
    /// Every label still on the ring, as data, so they can be laid out again
    /// after a resize or an axis change.
    private var allLabels: [WaterfallPlacedLabel] = []

    private func addTimestampLayer(_ text: String, absoluteRow: Int) {
        let group = CALayer()
        group.setValue(absoluteRow, forKey: Self.absRowKey)
        group.setValue(text, forKey: Self.textKey)

        let line = CALayer()
        line.name = "line"
        line.backgroundColor = UIColor.yellow.cgColor
        group.addSublayer(line)

        let label = Self.makePill(text, size: 10, weight: .regular, color: .white, background: Self.pillBackground)
        label.name = "label"
        group.addSublayer(label)

        timestampsLayer.addSublayer(group)
        layoutTimestampLayer(group)
    }

    /// Line on the exact row; the time above it (the newer side), like the
    /// slot boundary in most waterfalls.
    private func layoutTimestampLayer(_ group: CALayer) {
        guard let absRow = group.value(forKey: Self.absRowKey) as? Int else { return }
        let y = -CGFloat(absRow) * Self.pointsPerRow
        group.frame = CGRect(x: 0, y: y, width: bounds.width, height: 1)
        for sub in group.sublayers ?? [] {
            switch sub.name {
            case "line":
                sub.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
            case "label":
                let size = sub.bounds.size
                sub.frame = CGRect(x: bounds.width - 4 - size.width, y: -size.height - 2, width: size.width, height: size.height)
            default:
                break
            }
        }
    }

    private func relayoutAllLabels() {
        for sub in labelsLayer.sublayers ?? [] { sub.removeFromSuperlayer() }
        // Labels from one decode share anchor and span; lay each such batch out
        // together so neighbours on close frequencies get separate lanes.
        let batches = Dictionary(grouping: allLabels) { "\($0.anchorRow)/\($0.spanRows)" }
        for batch in batches.values { layoutLabelBatch(batch) }
    }

    private static let labelBoxHeight: CGFloat = 14   // text height, becomes the width once rotated
    private static let labelFontSize: CGFloat = 10

    /// Adds layers for `batch`, splitting labels whose frequencies are too
    /// close to be drawn side by side into lanes along the signal's length.
    private func layoutLabelBatch(_ batch: [WaterfallPlacedLabel]) {
        let boxWidth = Self.labelBoxHeight + 2
        let sorted = batch.sorted { $0.label.frequency < $1.label.frequency }
        var group: [WaterfallPlacedLabel] = []
        var groupMaxX: CGFloat = -.infinity
        func flush() {
            for (i, placed) in group.enumerated() { addLabelLayer(placed, lane: i, lanes: group.count) }
            group.removeAll()
        }
        for placed in sorted {
            let px = x(forHz: placed.label.frequency)
            if !group.isEmpty && px >= groupMaxX { flush() }
            group.append(placed)
            groupMaxX = max(groupMaxX, px + boxWidth)
        }
        flush()
    }

    private static func color(for kind: WaterfallLabel.Kind) -> UIColor {
        switch kind {
        case .forMe: return UIColor(red: 1.0, green: 0.55, blue: 0.6, alpha: 1)
        case .cq: return UIColor(red: 1.0, green: 0.9, blue: 0.25, alpha: 1)
        case .other: return .white
        }
    }

    /// One label, rotated −90° so it reads upward along the signal.
    /// - Parameters:
    ///   - lane: which of `lanes` slots along the signal this label takes when
    ///     several decodes sit on neighbouring frequencies.
    private func addLabelLayer(_ placed: WaterfallPlacedLabel, lane: Int, lanes: Int) {
        let text = placed.label.text
        let color = Self.color(for: placed.label.kind)
        let label = Self.makePill(
            text, size: Self.labelFontSize, weight: .bold, color: color,
            background: Self.pillBackground, height: Self.labelBoxHeight
        )
        label.setValue(placed.anchorRow, forKey: Self.absRowKey)
        let textWidth = label.bounds.width
        let boxHeight = Self.labelBoxHeight
        if placed.label.isWorked {
            // Already in the log: struck through and dimmed, still readable.
            label.opacity = 0.7
            let strike = CALayer()
            strike.backgroundColor = color.cgColor
            strike.frame = CGRect(x: 3, y: (boxHeight / 2).rounded(), width: textWidth - 6, height: 1)
            label.addSublayer(strike)
        }

        // Rotated −90° around its centre, so position it as an upright box.
        // Rows grow upward on screen (y = −row), so the signal's start is at
        // anchorY and it runs to anchorY − span.
        let anchorY = -CGFloat(placed.anchorRow) * Self.pointsPerRow
        let centreY: CGFloat
        if placed.spanRows > 0 {
            // Centre the label on its lane's share of the signal.
            let span = CGFloat(placed.spanRows) * Self.pointsPerRow
            let laneTop = anchorY - span * CGFloat(lane + 1) / CGFloat(lanes)
            let laneBottom = anchorY - span * CGFloat(lane) / CGFloat(lanes)
            centreY = (laneTop + laneBottom) / 2
        } else {
            // Start unknown: hang from the anchor, later lanes further down.
            centreY = anchorY + textWidth / 2 + CGFloat(lane) * (textWidth + 4)
        }
        // Lanes past the first also step one box to the right, so labels
        // longer than their share of the signal still do not cross.
        let laneX = CGFloat(lane) * (boxHeight + 2)
        label.position = CGPoint(x: x(forHz: placed.label.frequency) + boxHeight / 2 + laneX, y: centreY)
        label.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        labelsLayer.addSublayer(label)
    }

    // MARK: Static overlay

    private func rebuildStaticLayer() {
        for sub in staticLayer.sublayers ?? [] { sub.removeFromSuperlayer() }
        guard let style, style.showOverlay, bounds.width > 1, bounds.height > 1 else { return }
        let w = bounds.width
        let h = bounds.height

        if style.showFrequencyTicks {
            let stepHz = 500.0
            let path = UIBezierPath()
            let firstTick = (style.minDisplayHz / stepHz).rounded(.up) * stepHz
            var previousLabelMaxX: CGFloat = -.infinity
            for hz in stride(from: firstTick, through: style.maxDisplayHz, by: stepHz) {
                let tx = x(forHz: hz)
                path.move(to: CGPoint(x: tx, y: headerHeight))
                path.addLine(to: CGPoint(x: tx, y: h))
                let label = Self.makePill(
                    String(format: "%.1f kHz", hz / 1000), size: 10, weight: .regular,
                    color: .white, background: Self.pillBackground
                )
                let size = label.bounds.size
                // The last label would run off the right edge: flip it, and
                // drop it if that would run into the previous one.
                let fitsRight = tx + 2 + size.width <= w
                let originX = fitsRight ? tx + 2 : tx - 2 - size.width
                if originX < previousLabelMaxX + 2 { continue }
                label.frame = CGRect(x: originX, y: 1, width: size.width, height: size.height)
                staticLayer.addSublayer(label)
                previousLabelMaxX = originX + size.width
            }
            let ticks = CAShapeLayer()
            ticks.path = path.cgPath
            // Dark, so the grid reads over the yellow/cyan body of the
            // palette as well as over the blue floor.
            ticks.strokeColor = UIColor.black.withAlphaComponent(0.45).cgColor
            ticks.lineWidth = 1
            ticks.fillColor = nil
            staticLayer.addSublayer(ticks)
        }

        if style.showFrequencyMarker {
            let bandwidthHz = WaterfallViewModel.occupiedBandwidthHz(isFT4: style.isFT4)
            let path = UIBezierPath()
            for hz in [style.txFrequency, style.txFrequency + bandwidthHz] {
                let mx = x(forHz: hz)
                path.move(to: CGPoint(x: mx, y: headerHeight + 15))
                path.addLine(to: CGPoint(x: mx, y: h))
            }
            let lines = CAShapeLayer()
            lines.path = path.cgPath
            lines.strokeColor = UIColor.red.cgColor
            lines.lineWidth = 1
            lines.fillColor = nil
            staticLayer.addSublayer(lines)

            let label = Self.makePill(
                String(format: "%.0f Hz", style.txFrequency), size: 10, weight: .semibold,
                color: .red, background: UIColor.white.withAlphaComponent(0.85), height: 18, padding: 10
            )
            // Centred on the band the signal occupies, not on its base tone.
            let bandCentreX = x(forHz: style.txFrequency + bandwidthHz / 2)
            label.frame = CGRect(
                x: bandCentreX - label.bounds.width / 2, y: headerHeight / 2 + 5,
                width: label.bounds.width, height: label.bounds.height
            )
            staticLayer.addSublayer(label)
        }
    }

    // MARK: Text helpers

    private static func font(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private static func measure(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGSize {
        (text as NSString).size(withAttributes: [.font: font(size: size, weight: weight)])
    }

    private static let pillBackground = UIColor.black.withAlphaComponent(0.55)

    private static func makeTextLayer(
        _ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.font = font(size: size, weight: weight)
        layer.fontSize = size
        layer.foregroundColor = color.cgColor
        layer.contentsScale = UIScreen.main.scale
        layer.truncationMode = .none
        layer.isWrapped = false
        layer.alignmentMode = .center
        return layer
    }

    /// A rounded pill with `text` centred in it, both ways. CATextLayer only
    /// aligns horizontally, so the text sits in a child sized to the font's
    /// line height. The pill's `bounds` are set; place it with `frame` or
    /// `position`.
    private static func makePill(
        _ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor,
        background: UIColor, height: CGFloat = 14, padding: CGFloat = 8
    ) -> CALayer {
        let uiFont = font(size: size, weight: weight)
        let textSize = (text as NSString).size(withAttributes: [.font: uiFont])
        let pill = CALayer()
        pill.bounds = CGRect(x: 0, y: 0, width: (textSize.width + padding).rounded(.up), height: height)
        pill.backgroundColor = background.cgColor
        pill.cornerRadius = 3
        pill.contentsScale = UIScreen.main.scale

        let label = makeTextLayer(text, size: size, weight: weight, color: color)
        let lineHeight = uiFont.lineHeight.rounded(.up)
        label.frame = CGRect(x: 0, y: ((height - lineHeight) / 2).rounded(), width: pill.bounds.width, height: lineHeight)
        pill.addSublayer(label)
        return pill
    }
}

// MARK: - Metal renderer

/// Owns the ring texture and draws it as one quad, newest row at the top.
final class WaterfallMetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var texture: MTLTexture?
    private var ringHeight = 0
    private var writeRow = 0
    var visibleRows = 1

    private struct Uniforms {
        var writeRow: Float
        var visibleRows: Float
        var ringHeight: Float
        var padding: Float = 0
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 pos [[position]]; float2 uv; };
    struct Uniforms { float writeRow; float visibleRows; float ringHeight; float padding; };
    vertex VOut wf_vertex(uint vid [[vertex_id]]) {
        float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        VOut o;
        o.pos = float4(p[vid], 0, 1);
        o.uv = float2((p[vid].x + 1) * 0.5, (1 - p[vid].y) * 0.5); // uv.y = 0 at the top
        return o;
    }
    fragment float4 wf_fragment(VOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant Uniforms &u [[buffer(0)]]) {
        // Newest row (writeRow - 1) at the top, visibleRows rows down to the
        // oldest shown; the ring wraps.
        float row = u.writeRow - 1e-4 - in.uv.y * u.visibleRows;
        row = fmod(row + u.ringHeight, u.ringHeight);
        // Linear in x; sampling at the row centre keeps rows crisp in y.
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return tex.sample(s, float2(in.uv.x, (floor(row) + 0.5) / u.ringHeight));
    }
    """

    /// `nil` when Metal is unavailable (never on a real iPhone).
    static func make() -> WaterfallMetalRenderer? {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue(),
            let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
            let vertex = library.makeFunction(name: "wf_vertex"),
            let fragment = library.makeFunction(name: "wf_fragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return WaterfallMetalRenderer(device: device, queue: queue, pipeline: pipeline)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState) {
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        super.init()
    }

    func reset(width: Int, height: Int, pixels: UnsafeBufferPointer<UInt32>, writeRow: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor), let base = pixels.baseAddress,
              pixels.count >= width * height
        else { return }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: base,
            bytesPerRow: width * MemoryLayout<UInt32>.stride
        )
        self.texture = texture
        ringHeight = height
        self.writeRow = writeRow
    }

    func append(row: UnsafeBufferPointer<UInt32>, ringRow: Int) {
        guard let texture, let base = row.baseAddress, row.count == texture.width, ringRow < ringHeight else { return }
        texture.replace(
            region: MTLRegionMake2D(0, ringRow, texture.width, 1),
            mipmapLevel: 0,
            withBytes: base,
            bytesPerRow: texture.width * MemoryLayout<UInt32>.stride
        )
        writeRow = (ringRow + 1) % ringHeight
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let texture,
            let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let buffer = queue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        var uniforms = Uniforms(
            writeRow: Float(writeRow),
            visibleRows: Float(min(max(visibleRows, 1), ringHeight)),
            ringHeight: Float(ringHeight)
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

// MARK: - SwiftUI host

/// Hosts `WaterfallRenderView`, attaches it to the view model and forwards
/// the overlay style. Nothing here changes per row.
struct WaterfallRenderRepresentable: UIViewRepresentable {
    let viewModel: WaterfallViewModel
    let style: WaterfallOverlayStyle

    func makeUIView(context: Context) -> WaterfallRenderView {
        let view = WaterfallRenderView(frame: .zero)
        view.apply(style: style)
        viewModel.attach(view)
        return view
    }

    func updateUIView(_ view: WaterfallRenderView, context: Context) {
        view.apply(style: style)
    }

    static func dismantleUIView(_ view: WaterfallRenderView, coordinator: ()) {
        // The view model only holds the sink weakly; nothing to detach explicitly.
    }
}
