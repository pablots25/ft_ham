//
//  FullScreenWaterfallView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 24/11/25.
//

import SwiftUI
import TipKit

// MARK: - Native Tip (Tutorial) definition
struct FrequencyTip: Tip {
    var title: Text { Text("Adjust Frequency") }
    var message: Text? { Text("Tap here to enable or disable frequency adjustments directly on the waterfall.") }
    var image: Image? { Image(systemName: "arrow.left.arrow.right") }
}

// Simple Tutorial Item
struct ButtonTutorialItem: Identifiable {
    let id = UUID()
    let iconName: String
    let description: String
}

struct FullScreenWaterfallView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var isSettingFrequency: Bool = false
    @State private var isSettingsExpanded: Bool = false
    @AppStorage("hasSeenFloatingButtonTutorial") private var hasSeenTutorial: Bool = false
    @State private var showTutorial: Bool = true

    private let frequencyTip = FrequencyTip()
    
    // Tutorial items for all toolbar buttons
    let tutorialItems: [ButtonTutorialItem] = [
        ButtonTutorialItem(iconName: "arrow.left.arrow.right", description: "Toggle frequency adjustment"),
        ButtonTutorialItem(iconName: "eye", description: "Show/hide all overlays"),
        ButtonTutorialItem(iconName: "clock", description: "Show/hide timestamps"),
        ButtonTutorialItem(iconName: "message.and.waveform", description: "Show/hide vertical labels"),
        ButtonTutorialItem(iconName: "lines.measurement.horizontal", description: "Show/hide frequency ticks"),
        ButtonTutorialItem(iconName: "ruler", description: "Show/hide frequency marker")
    ]
    
    var body: some View {
        GeometryReader { geo in
            // Detect landscape normally, force portrait on iPad
            let isLandscape = (UIDevice.current.userInterfaceIdiom == .pad) ? false : (geo.size.width > geo.size.height)

            
            ZStack {
                Group {
                    if isLandscape {
                        landscapeLayout(width: geo.size.width)
                    } else {
                        portraitLayout()
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isLandscape)
                .frame(width: geo.size.width, height: geo.size.height)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isSettingsExpanded {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                isSettingsExpanded = false
                            }
                        }
                    }
                )
            }

            // Simple overlay tutorial
            if showTutorial && !hasSeenTutorial {
                tutorialOverlay
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            if viewModel.isListening {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        unifiedControlBar
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, isLandscape ? 5 : 130)
                }
                .zIndex(100)
                .frame(maxWidth: .infinity)
            }
        }
    }

    
    // MARK: - Simple Tutorial Overlay
    private var tutorialOverlay: some View {
        ZStack {
            // Full screen semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(tutorialItems) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.iconName)
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 30)
                            Text(item.description)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .padding(.trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top)
                    
                    Divider()
                        .background(Color.white.opacity(0.5))
                        .padding(.vertical, 8)
                    
                    Button("Got it") {
                        hasSeenTutorial = true
                        showTutorial = false
                        isSettingsExpanded = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom)
                    .padding(.horizontal)
                    
                }
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.85)))
                .padding(.horizontal, 25)
                .padding(.bottom, 170)
            }
        }
        .onAppear {
            isSettingsExpanded = true
        }
    }


    // MARK: - Toolbar
    private var unifiedControlBar: some View {
        HStack(spacing: 12) {
            
            // Frequency Adjustment Button
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.3)) {
                    isSettingFrequency.toggle()
                    isSettingsExpanded = false
                    frequencyTip.invalidate(reason: .actionPerformed)
                    hasSeenTutorial = true
                }
            } label: {
                Image(systemName: isSettingFrequency ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                    .foregroundStyle(isSettingFrequency ? .green : .primary)
            }
            .padding(.horizontal, isSettingFrequency ? 20 : 1)
            .frame(height: 30)
            
            
            if(!isSettingFrequency){
                // Settings Button
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.3)) {
                        isSettingsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(isSettingsExpanded ? .green : .primary)
                }
            }
        
            if isSettingsExpanded {
                Divider()
                
                // Show All Overlays Toggle
                Button {
                    viewModel.waterfallVM.toggleShowAllOverlays()
                } label: {
                    Image(systemName: viewModel.waterfallVM.showOverlay ? "eye.fill" : "eye")
                        .foregroundStyle(viewModel.waterfallVM.showOverlay ? .blue : .primary)
                }
                
                Divider()

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
                    Image(systemName:"lines.measurement.horizontal")
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
                .padding(.trailing, 5)
            }
        
            
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .frame(height: 40)
        .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.3), value: isSettingsExpanded)
    }

}

// MARK: - Layouts
private extension FullScreenWaterfallView {
    // MARK: - Portrait layout
    
    func portraitLayout() -> some View {
        VStack(spacing: 10) {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            
            LazyVGrid(columns: columns, spacing: 12) {
                StatusView()
                    .gridCellColumns(2)
                    .frame(maxWidth: .infinity)
                ClockView()
                    .gridCellColumns(2)
            }
            .padding(.horizontal)
            
            TransmissionButtonsBar()
                .padding(.bottom, 5)
                .padding(.horizontal)
            
            WaterfallView(
                viewModel: viewModel.waterfallVM,
                ft8ViewModel: viewModel,
                isSettingFrequency: $isSettingFrequency
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 5)
            
            VStack {
                QSOStatusView()
                MessageSelector()
            }
            .padding(.horizontal, 40)
            .padding(.bottom)
        }
    }
    
    func landscapeLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            controlPanel
                .frame(width: width * 0.45)
            Divider()
            
            WaterfallView(
                viewModel: viewModel.waterfallVM,
                ft8ViewModel: viewModel,
                isSettingFrequency: $isSettingFrequency
            )
            .frame(width: width * 0.55)
            .padding(.horizontal)
            .padding(.trailing)
        }
    }
    
    private var controlPanel: some View {
        VStack(spacing: 20) {
            TransmissionButtonsBar()
            Divider()
            QSOStatusView().padding(.horizontal)
//            DXInfoFields().padding(.horizontal)
            MessageSelector().padding(.horizontal)
        }
    }
    
}

#Preview("FullScreenWaterfallView") {
    FullScreenWaterfallView()
        .environmentObject(FT8ViewModel(txMessages: PreviewMocks.txMessages, rxMessages: PreviewMocks.rxMessages))
}
