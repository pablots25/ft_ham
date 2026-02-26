//
//  WaterfallDashboardView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 2026-02-26.
//

import SwiftUI

struct WaterfallDashboardView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var isSettingFrequency: Bool = false
    @State private var isSettingsExpanded: Bool = false
    @AppStorage("hasSeenFloatingButtonTutorial") private var hasSeenTutorial: Bool = false
    @State private var showTutorial: Bool = true

    var body: some View {
        GeometryReader { _ in
            ZStack {
                WaterfallView(
                    viewModel: viewModel.waterfallVM,
                    ft8ViewModel: viewModel,
                    isSettingFrequency: $isSettingFrequency
                )
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Control bar overlay
                if viewModel.isListening {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            controlBarWithToggle
                        }
                        .padding(.trailing, LayoutConstants.standardPadding)
                        .padding(.bottom, LayoutConstants.standardPadding)
                    }
                    .zIndex(100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Control Bar

    private var controlBarWithToggle: some View {
        HStack(spacing: LayoutConstants.standardSpacing) {
            // Frequency Adjustment Button
            Button {
                withAnimation(.spring(response: LayoutConstants.springResponse, dampingFraction: 0.7, blendDuration: LayoutConstants.springBlending)) {
                    isSettingFrequency.toggle()
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(isSettingFrequency ? .green : .primary)
            }
            .padding(.horizontal, isSettingFrequency ? LayoutConstants.largePadding : 1)
            .frame(height: 30)
            
            if !isSettingFrequency {
                // Settings Toggle Button
                Button {
                    withAnimation(.spring(response: LayoutConstants.springResponse, dampingFraction: 0.7, blendDuration: LayoutConstants.springBlending)) {
                        isSettingsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(isSettingsExpanded ? .green : .primary)
                }
            }
            
            if isSettingsExpanded {
                Divider()
                    .frame(height: 20)
                
                expandedControls
            }
        }
        .padding(.horizontal, LayoutConstants.standardPadding)
        .padding(.vertical, LayoutConstants.compactPadding - 2)
        .background(
            RoundedRectangle(cornerRadius: LayoutConstants.largeCornerRadius, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LayoutConstants.largeCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .frame(height: LayoutConstants.controlBarHeight)
        .animation(.spring(response: LayoutConstants.springResponse, dampingFraction: LayoutConstants.springDamping, blendDuration: LayoutConstants.springBlending), value: isSettingsExpanded)
    }
    
    private var expandedControls: some View {
        HStack(spacing: LayoutConstants.standardSpacing) {
            // Show All Overlays Toggle
            Button {
                viewModel.waterfallVM.toggleShowAllOverlays()
            } label: {
                Image(systemName: viewModel.waterfallVM.showOverlay ? "eye.fill" : "eye.slash")
                    .foregroundStyle(viewModel.waterfallVM.showOverlay ? .blue : .primary)
            }

            // Show Timestamps Toggle
            Button {
                viewModel.waterfallVM.toggleTimestamps()
            } label: {
                Image(systemName: viewModel.waterfallVM.showTimestamps ? "clock.fill" : "clock")
                    .foregroundStyle(viewModel.waterfallVM.showTimestamps ? .blue : .primary)
            }

            // Show Vertical Labels Toggle
            Button {
                viewModel.waterfallVM.toggleVerticalLabels()
            } label: {
                Image(
                    systemName: viewModel.waterfallVM.showVerticalLabels ? "message.and.waveform.fill" : "message.and.waveform"
                )
                    .foregroundStyle(viewModel.waterfallVM.showVerticalLabels ? .blue : .primary)
            }

            // Show Frequency Ticks Toggle
            Button {
                viewModel.waterfallVM.toggleFrequencyTicks()
            } label: {
                Image(systemName: "lines.measurement.horizontal")
                    .renderingMode(.template)
                    .foregroundStyle(viewModel.waterfallVM.showFrequencyTicks ? .blue : .primary)
            }

            // Show Frequency Marker Toggle
            Button {
                viewModel.waterfallVM.toggleFrequencyMarker()
            } label: {
                Image(systemName: viewModel.waterfallVM.showFrequencyMarker ? "ruler.fill" : "ruler")
                    .foregroundStyle(viewModel.waterfallVM.showFrequencyMarker ? .blue : .primary)
            }
            .padding(.trailing, LayoutConstants.compactPadding - 3)
        }
    }
}

#Preview("Waterfall Dashboard") {
    WaterfallDashboardView()
        .environmentObject(
            FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            )
        )
}
