//
//  WaterfallView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/11/25.
//

import SwiftUI

struct WaterfallView: View {
    @ObservedObject var viewModel: WaterfallViewModel
    @ObservedObject var ft8ViewModel: FT8ViewModel

    @Binding var isSettingFrequency: Bool

    @State private var cursorX: CGFloat? = nil
    @State private var cursorFrequency: Double = 0
    /// Identifies this view in the view model's viewer registry, so rendering
    /// stops when no waterfall is on screen (other tab, dashboard hidden...).
    @State private var viewerID = UUID()

    private static func rows(for height: CGFloat) -> Int {
        // Cap at 600 rows: full-screen on a large iPhone gives ~930 pts but
        // you only need a few hundred rows of scroll history. Fewer rows = less
        // pixel-copy work per render frame.
        min(max(Int(height), 1) + 1, 600)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let waterfall = viewModel.waterfallImage {
                    let w = max(geo.size.width, 1)
                    let h = max(geo.size.height, 1)

                    waterfall
                        .resizable()
                        .frame(width: w, height: h, alignment: .bottom)
                        .clipped()

                    // Overlay data is passed as plain values (Equatable) so the
                    // Canvas below only redraws when something it draws changed.
                    // Rows are addressed in image rows, not points: the image is
                    // stretched to the view height, and the overlay scales to match.
                    let imageRows = max(viewModel.renderedRows, 1)
                    WaterfallOverlayView(
                        overlayState: viewModel.overlayState,
                        config: viewModel.config,
                        timestamps: viewModel.timestampsForOverlay(height: imageRows),
                        verticalLabels: viewModel.verticalLabelsForOverlay(height: imageRows),
                        txFrequency: ft8ViewModel.frequency,
                        isFT4: ft8ViewModel.isFT4,
                        imageRows: imageRows
                    )
                } else {
                    Text("Waiting for audio data...")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let cx = cursorX {
                    FrequencyCursorView(x: cx, frequency: cursorFrequency, height: geo.size.height)
                        .zIndex(1)
                }
            }
            .onAppear {
                viewModel.viewerAppeared(viewerID, rows: Self.rows(for: geo.size.height))
            }
            .onChange(of: geo.size.height) { newHeight in
                viewModel.viewerAppeared(viewerID, rows: Self.rows(for: newHeight))
            }
            .onDisappear {
                viewModel.viewerDisappeared(viewerID)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let w = max(geo.size.width, 1)
                        let x = min(max(value.location.x, 0), w)

                        cursorX = x
                        cursorFrequency = viewModel.frequencyAtPixel(x: x, width: w)

                        if isSettingFrequency {
                            // Keep the whole signal inside the decoder's passband
                            // even when the finger runs past the band edges.
                            ft8ViewModel.frequency = cursorFrequency.clamped(
                                to: WaterfallViewModel.txFrequencyRange(isFT4: ft8ViewModel.isFT4)
                            )
                        }
                    }
                    .onEnded { _ in
                        cursorX = nil
                        if isSettingFrequency { isSettingFrequency = false }
                    }
            )
        }
    }
}

struct WaterfallOverlayView: View {
    // Observe only the lightweight overlay toggles. Everything else comes in
    // as values so this Canvas is not redrawn on every FT8ViewModel publish
    // (which is what observing the view model here used to cause).
    @ObservedObject var overlayState: WaterfallOverlayState
    let config: WaterfallViewModel.Config
    let timestamps: [TimestampOverlay]
    let verticalLabels: [VerticalLabelOverlay]
    let txFrequency: Double
    let isFT4: Bool
    /// Rows in the image under this overlay; row `r` is drawn at
    /// `r * size.height / imageRows`.
    let imageRows: Int
    let headerHeight: CGFloat = 15

    var body: some View {
        Canvas { ctx, size in
            guard overlayState.showOverlay, size.width > 1, size.height > 1 else { return }
            let w = size.width
            let h = size.height
            let bodyOffset = headerHeight
            let rowScale = h / CGFloat(max(imageRows, 1))

            let minFreq = Double(config.minDisplayFrequency)
            let maxFreq = Double(config.maxDisplayFrequency)
            guard maxFreq > minFreq else { return }
            // Same axis as the pixel rows: see WaterfallViewModel.xPosition(for:in:).
            let xFor: (Double) -> CGFloat = { hz in
                CGFloat((hz - minFreq) / (maxFreq - minFreq)) * w
            }

            // Frequency ticks
            if overlayState.showFrequencyTicks {
                let stepHz = 500.0
                let firstTick = (minFreq / stepHz).rounded(.up) * stepHz
                for f in stride(from: firstTick, through: maxFreq, by: stepHz) {
                    let x = xFor(f)
                    guard x.isFinite else { continue }
                    
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: bodyOffset))
                    path.addLine(to: CGPoint(x: x, y: h))
                    ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)
                    
                    // The last label would run off the right edge; flip it.
                    let fitsRight = x + 45 <= w
                    ctx.draw(
                        Text(String(format: "%.1f kHz", f / 1000))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white),
                        at: CGPoint(x: fitsRight ? x + 2 : x - 2, y: 0),
                        anchor: fitsRight ? .topLeading : .topTrailing
                    )
                }
            }

            // Horizontal timestamp lines, on the exact row the slot started
            // (newer rows are above it, so the label sits on the newer side).
            for overlay in timestamps {
                let y = CGFloat(overlay.row) * rowScale
                
                // Line
                let path = Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
                ctx.stroke(path, with: .color(.yellow), lineWidth: 1)
                
                // Label — below the line only while it is still too close to
                // the top edge to fit above it.
                let labelHeight: CGFloat = 12
                let labelAbove = y >= labelHeight
                ctx.draw(
                    Text(overlay.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white),
                    at: CGPoint(x: w - 4, y: labelAbove ? y - 1 : y + 1),
                    anchor: labelAbove ? .bottomTrailing : .topTrailing
                )
            }

            if overlayState.showFrequencyMarker {
                // TX frequency indicator
                let txFreq = txFrequency
                let txX = xFor(txFreq)
                guard txX.isFinite else { return }
                
                let labelText = String(format: "%.0f Hz", txFreq)
                let approxCharWidth: CGFloat = 6.0
                let approxHeight: CGFloat = 12.0
                let labelWidth = CGFloat(labelText.count) * approxCharWidth + 8.0
                let labelHeight = approxHeight + 6.0
                let rect = CGRect(
                    x: txX - labelWidth / 2,
                    y: headerHeight / 2 + 5,
                    width: labelWidth,
                    height: labelHeight
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.8)))
                ctx.draw(
                    Text(labelText)
                        .font(.system(size: 10))
                        .foregroundColor(.red),
                    at: CGPoint(x: rect.midX, y: rect.midY),
                    anchor: .center
                )
                
                // Occupied bandwidth above the base tone: 8 tones × 6.25 Hz
                // for FT8, 4 tones × 20.83 Hz for FT4.
                let bandwidthHz = WaterfallViewModel.occupiedBandwidthHz(isFT4: isFT4)
                for freq in [txFreq, txFreq + bandwidthHz] {
                    let x = xFor(freq)
                    let path = Path { path in
                        path.move(to: CGPoint(x: x, y: bodyOffset + 15))
                        path.addLine(to: CGPoint(x: x, y: h))
                    }
                    ctx.stroke(path, with: .color(.red), lineWidth: 1)
                }
            }

            // Vertical moving labels
            for overlay in verticalLabels {
                let x = xFor(overlay.frequency)
                var tctx = ctx
                let text = overlay.text
                let approxCharWidth: CGFloat = 6.0
                let approxCharHeight: CGFloat = 12.0
                let textWidth = CGFloat(text.count) * approxCharWidth
                let textHeight = approxCharHeight
                // Text runs upward from the anchor row (the decode moment).
                let y = CGFloat(overlay.row) * rowScale + textWidth

                tctx.translateBy(x: x, y: y)
                tctx.rotate(by: .radians(-.pi / 2))

                let backgroundRect = CGRect(
                    x: -2, y: -2,
                    width: textWidth + 4,
                    height: textHeight + 4
                )
                tctx.fill(Path(roundedRect: backgroundRect, cornerRadius: 4), with: .color(.black.opacity(0.3)))
                tctx.draw(
                    Text(text)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white),
                    at: .zero,
                    anchor: .topLeading
                )
            }

        }
        .allowsHitTesting(false)
    }
}

struct FrequencyCursorView: View {
    let x: CGFloat
    let frequency: Double
    let height: CGFloat // waterfall height
    let labelOffset: CGFloat = 40 // pixels below top
    let labelPadding: CGFloat = 4 // padding inside label

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.yellow.opacity(0.8))
                .frame(width: 1, height: height)
                .position(x: x, y: height / 2)

            GeometryReader { geo in
                let labelWidth: CGFloat = 60
                let adjustedX = min(x + 35, geo.size.width - labelWidth - labelPadding)

                Text(String(format: "%.0f Hz", frequency))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(labelPadding)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.yellow)
                    .cornerRadius(4)
                    .position(x: adjustedX, y: labelOffset)
            }
        }
    }
}

