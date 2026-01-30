//
//  WaterfallView.swift
//  ft8_ham
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

                    if viewModel.showOverlay {
                        WaterfallOverlayView(
                            viewModel: viewModel,
                            ft8ViewModel: ft8ViewModel,
                            width: Int(geo.size.width),
                            height: Int(geo.size.height)
                        )
                    }
                } else {
                    Text("Waiting for audio data...")
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let cx = cursorX {
                    FrequencyCursorView(x: cx, frequency: cursorFrequency, height: geo.size.height)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Ensure enough waterfall rows
                let rows = max(Int(geo.size.height), 1) + 1
                viewModel.visibleRows = rows
                viewModel.ensureBufferCanHold(visibleRows: rows)
            }
            .onChange(of: geo.size.height) { _, newHeight in
                let rows = max(Int(newHeight), 1) + 1
                viewModel.visibleRows = rows
                viewModel.ensureBufferCanHold(visibleRows: rows)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let w = max(geo.size.width, 1)
                        let x = min(max(value.location.x, 0), w)

                        cursorX = x
                        cursorFrequency = viewModel.frequencyAtPixel(x: x, width: w)

                        if isSettingFrequency {
                            ft8ViewModel.frequency = cursorFrequency
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
    @ObservedObject var viewModel: WaterfallViewModel
    @ObservedObject var ft8ViewModel: FT8ViewModel

    let width: Int
    let height: Int
    let headerHeight: CGFloat = 15

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 1, size.height > 1 else { return }
            let w = size.width
            let h = size.height
            let bodyOffset = headerHeight

            let maxFreq = Double(viewModel.config.maxDisplayFrequency) * 4.0
            guard maxFreq > 0 else { return }

            // Frequency ticks
            if viewModel.showFrequencyTicks {
                let stepHz = 500.0
                for f in stride(from: 0.0, through: maxFreq, by: stepHz) {
                    let x = CGFloat(f / maxFreq) * w
                    guard x.isFinite else { continue }
                    
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: bodyOffset))
                    path.addLine(to: CGPoint(x: x, y: h))
                    ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)
                    
                    ctx.draw(
                        Text(String(format: "%.1f kHz", f / 1000))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.white),
                        at: CGPoint(x: x + 2, y: 0),
                        anchor: .topLeading
                    )
                }
            }

            // Horizontal timestamp lines
            let timestamps = viewModel.timestampsForOverlay(height: Int(size.height))
            for overlay in timestamps {
                let y = CGFloat(overlay.row) + bodyOffset
                
                // Line
                let path = Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
                ctx.stroke(path, with: .color(.yellow), lineWidth: 1)
                
                // Label
                ctx.draw(
                    Text(overlay.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white),
                    at: CGPoint(x: w - 4, y: CGFloat(overlay.row)),
                    anchor: .topTrailing
                )
            }

            if viewModel.showFrequencyMarker {
                // TX frequency indicator
                let txFreq = ft8ViewModel.frequency
                let txX = CGFloat(txFreq / maxFreq) * w
                guard txX.isFinite else { return }
                
                let label = Text(String(format: "%.0f Hz", txFreq))
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                
                let resolved = ctx.resolve(label)
                let labelSize = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                
                let rect = CGRect(
                    x: txX - labelSize.width / 2 - 2,
                    y: headerHeight / 2 + 5,
                    width: labelSize.width + 4,
                    height: labelSize.height + 4
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.8)))
                ctx.draw(label, at: CGPoint(x: txX, y: rect.midY), anchor: .center)
                
                let bandwidthHz = (ft8ViewModel.isFT4 ? 90.0 : 50.0) * 2
                for freq in [txFreq, txFreq + bandwidthHz] {
                    let x = CGFloat(freq / maxFreq) * w
                    let path = Path { path in
                        path.move(to: CGPoint(x: x, y: bodyOffset + 15))
                        path.addLine(to: CGPoint(x: x, y: h))
                    }
                    ctx.stroke(path, with: .color(.red), lineWidth: 1)
                }
            }

            // Vertical moving labels
            let vLabels = viewModel.verticalLabelsForOverlay(height: Int(size.height))
            for overlay in vLabels {
                let x = CGFloat(overlay.frequency / maxFreq) * w
                var tctx = ctx

                let resolvedText = tctx.resolve(
                    Text(overlay.text)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
                let textSize = resolvedText.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
                let y = CGFloat(overlay.row) + bodyOffset + textSize.width

                tctx.translateBy(x: x, y: y)
                tctx.rotate(by: .radians(-.pi / 2))

                let backgroundRect = CGRect(
                    x: -2, y: -2,
                    width: textSize.width + 4,
                    height: textSize.height + 4
                )
                tctx.fill(Path(roundedRect: backgroundRect, cornerRadius: 4), with: .color(.black.opacity(0.3)))
                tctx.draw(resolvedText, at: .zero, anchor: .topLeading)
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
                    .foregroundStyle(.yellow)
                    .cornerRadius(4)
                    .position(x: adjustedX, y: labelOffset)
            }
        }
    }
}
