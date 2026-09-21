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
    @ObservedObject private var overlayState: WaterfallOverlayState

    @Binding var isSettingFrequency: Bool

    @State private var cursorX: CGFloat? = nil
    @State private var cursorFrequency: Double = 0

    init(viewModel: WaterfallViewModel, ft8ViewModel: FT8ViewModel, isSettingFrequency: Binding<Bool>) {
        self.viewModel = viewModel
        self.ft8ViewModel = ft8ViewModel
        self.overlayState = viewModel.overlayState
        self._isSettingFrequency = isSettingFrequency
    }

    /// Everything the renderer's overlay depends on. Rows themselves never
    /// come through SwiftUI: the view model pushes them straight to the
    /// render view (see `WaterfallRenderView`).
    private var overlayStyle: WaterfallOverlayStyle {
        WaterfallOverlayStyle(
            minDisplayHz: Double(viewModel.config.minDisplayFrequency),
            maxDisplayHz: Double(viewModel.config.maxDisplayFrequency),
            txFrequency: ft8ViewModel.frequency,
            isFT4: ft8ViewModel.isFT4,
            showOverlay: overlayState.showOverlay,
            showTimestamps: overlayState.showTimestamps,
            showVerticalLabels: overlayState.showVerticalLabels,
            showFrequencyTicks: overlayState.showFrequencyTicks,
            showFrequencyMarker: overlayState.showFrequencyMarker
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                WaterfallRenderRepresentable(viewModel: viewModel, style: overlayStyle)

                if !viewModel.hasData {
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
            .contentShape(Rectangle())
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

