//
//  ControlsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 23/11/25.
//

import SwiftUI

// MARK: - Transmission Buttons Bar

struct TransmissionButtonsBar: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    var body: some View {
        HStack {
            Button(viewModel.transmitLoopActive ? "Stop Auto TX" : "Start Auto TX") {
                viewModel.toggleTransmit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .tint(viewModel.transmitLoopActive ? .red : .blue)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.settingsLoaded)

            Button("Stop TX") {
                viewModel.stopCurrentTX()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .tint(viewModel.isTransmitting ? .red : .blue)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.settingsLoaded || !viewModel.isTransmitting)

            Button(viewModel.isListening ? "Stop RX" : "Start RX") {
                if viewModel.isListening {
                    Task { @MainActor in
                        await viewModel.stopSequencer()
                    }
                } else {
                    viewModel.startSequencer()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .tint(viewModel.isListening ? .red : .green)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.settingsLoaded)
        }
    }
}


// MARK: - DX Info Fields

struct DXInfoFields: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    var body: some View {
        HStack {
            HStack {
                Text("DX Call")
                TextField("", text: $viewModel.dxCallsign)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .keyboardType(.asciiCapable)
                    .disabled(true)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            HStack {
                Text("DX Grid")
                TextField("", text: $viewModel.dxLocator)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .keyboardType(.asciiCapable)
                    .disabled(true)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
        }
    }
}


// MARK: - Message Selector

struct MessageSelector: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var showGenMessages = false
    @State private var activeHelp: HelpTip?
    @State private var sheetDetent: PresentationDetent = .large

    // Local editable state for callsign/locator
    @State private var callsignText: String = ""
    @State private var locatorText: String = ""
    @State private var validCallsign = false
    @State private var validLocator = false

    var body: some View {
        VStack(spacing: 0){

            if viewModel.autoSequencingEnabled {
                Text(NSLocalizedString("Next message:", comment: "Label for next message field"))
                    .foregroundStyle(.gray)
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            }

            HStack {
                if !viewModel.autoSequencingEnabled {
                    Button("<") {
                        if let index = viewModel.selectedMessageIndex {
                            viewModel.selectedMessageIndex = (index - 1 + viewModel.allMessages.count) % viewModel.allMessages
                                .count
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                
                if let index = viewModel.selectedMessageIndex,
                   index >= 0,
                   index < viewModel.allMessages.count {
                    TextField("",text: $viewModel.allMessages[index])
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .disabled(true)
                        .foregroundStyle(.gray)
                } else {
                    TextField("", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .disabled(true)
                        .foregroundStyle(.gray)
                }
                
                
                if !viewModel.autoSequencingEnabled {
                    Button(">") {
                        if let index = viewModel.selectedMessageIndex {
                            viewModel.selectedMessageIndex = (index + 1) % viewModel.allMessages.count
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    showGenMessages = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showGenMessages) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: Callsign
                        CallsignFieldView(
                            callsignText: $callsignText,
                            validCallsign: $validCallsign,
                            onCommit: {
                                let text = callsignText.uppercased()
                                callsignText = text
                                if isValidCallsign(text) { viewModel.callsign = text }
                            }
                        )

                        // MARK: Auto GPS Toggle
                        ToggleRow(
                            labelKey: "Auto (from GPS)",
                            helpTip: .locatorGPS,
                            isOn: Binding(
                                get: { viewModel.autoLocatorFromGPS },
                                set: { viewModel.setAutoLocatorFromGPS($0) }
                            ),
                            activeHelp: $activeHelp
                        )

                        // MARK: Locator (only when GPS is off)
                        if !viewModel.autoLocatorFromGPS {
                            LocatorFieldView(
                                locatorText: $locatorText,
                                validLocator: $validLocator,
                                onCommit: {
                                    var text = locatorText.uppercased()
                                    text.removeAll(where: { $0.isWhitespace })
                                    if text.count > 4 { text = String(text.prefix(4)) }
                                    locatorText = text
                                    if isValidLocator(text) { viewModel.locator = text }
                                }
                            )
                        }
                        
                        BandPickerView(
                            selectedBand: $viewModel.selectedBand,
                            isFT4: viewModel.isFT4
                        )

                        Divider()

                        // MARK: CQ Options
                        ToggleRow(
                            labelKey: "Include Grid in CQ",
                            helpTip: .cqIncludeGrid,
                            isOn: $viewModel.cqIncludeGrid,
                            activeHelp: $activeHelp
                        )
                        Divider()
                        CQModifierView()
                        Divider()
                        GenMessagesView()

                        // MARK: Full Configuration Link
                        Button {
                            showGenMessages = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(name: .navigateToConfiguration, object: nil)
                            }
                        } label: {
                            Label("Go to configuration", systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.visible)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Quick config")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showGenMessages = false }
                    }
                }
                .onAppear {
                    callsignText = viewModel.callsign
                    locatorText = viewModel.locator
                    validCallsign = isValidCallsign(viewModel.callsign)
                    validLocator = isValidLocator(viewModel.locator)
                }
                .onChange(of: viewModel.selectedMessageIndex) { _ in
                    showGenMessages = false
                }
            }
            .presentationDetents([.medium, .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
    }

}

struct StatusView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    // private var statusText: String {
    //     if viewModel.isTransmitting {
    //         return String(localized: "Transmitting")
    //     } else if viewModel.transmitLoopActive {
    //         return String(localized: "Waiting...") // Armed for Auto TX
    //     } else if viewModel.isListening {
    //         return String(localized: "Listening")
    //     } else {
    //         return String(localized: "Not started")
    //     }
    // }


    private var statusText: String {
        if viewModel.isTransmitting {
            String(localized: "Transmitting")
        } else if viewModel.isListening {
            String(localized: "Listening")
        } else if viewModel.transmitLoopActive {
            String(localized: "Waiting...")
        } else {
            String(localized: "Not started")
        }
    }

    private var statusColor: Color {
        if viewModel.isTransmitting {
            return .red
        } else if viewModel.transmitLoopActive {
            return .yellow
        } else if viewModel.isListening {
            return .green
        } else {
            return .gray
        }
    }

    var body: some View {
        HStack {
            Text("Status:")
                .foregroundStyle(.gray)

            Text(statusText)
                .foregroundStyle(statusColor)
        }
        .font(.body)
    }
}

// MARK: - Clock View

struct ClockView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let currentUTC = DateFormatter.utcFormatterClock.string(from: context.date)

            Text("UTC: \(currentUTC)")
                .foregroundStyle(.gray)
                .font(.body)
        }
    }
}

struct TransmissionControlPanel: View {
    let showWaterfallDivider: Bool

    init(showWaterfallDivider: Bool = true) {
        self.showWaterfallDivider = showWaterfallDivider
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ClockView()
                    .frame(alignment: .leading)

                StatusView()
                    .frame(alignment: .leading)
            }

            TransmissionButtonsBar()

            if showWaterfallDivider {
                Divider()
            }
        }
    }
}


struct QSOStatusView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    
    private var statusColor: Color {
        switch viewModel.qsoManager.qsoState {
            // Idle
        case .idle: return .gray
            
            // CQ
        case .callingCQ: return .yellow
            //        case .listeningCQ: return .orange
            
            // Grid exchange
        case .sendingGrid: return .purple
            //        case .listeningGrid: return .blue
            
            // Report exchange
        case .sendingReport: return .purple
        case .listeningReport: return .blue
            
            // R-Report exchange
        case .sendingRReport: return .purple
        case .listeningRReport: return .blue
            
            // RRR / 73 exchange
        case .sendingRRR: return .purple
        case .listeningRRR: return .blue
        case .sending73: return .brown
            
            // Completed / Timeout
        case .completed: return .green
        case .timeout: return .red
        }
    }
    private var shouldShowRetry: Bool {
        viewModel.qsoManager.retryCounter > 0 && viewModel.qsoManager.isAwaitingResponse()
    }
    
    private var displayedRetryCount: Int {
        min(viewModel.qsoManager.retryCounter, viewModel.qsoManager.maxRetrySlots)
    }
    
    var body: some View {
        HStack {
            VStack(spacing: 2) {
                
                // Status + (x/y)
                HStack(spacing: 4) {
                    Text(viewModel.qsoManager.qsoState.description)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .layoutPriority(1)
                    
                    if shouldShowRetry {
                        Text("(\(displayedRetryCount)/\(viewModel.qsoManager.maxRetrySlots))")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    Spacer(minLength: 0)
                }
                
                // Callsign + Locator
                HStack(spacing: 2) {
                    if !viewModel.qsoManager.lockedDXCallsign.isEmpty {
                        Text(viewModel.qsoManager.lockedDXCallsign)
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    
                    if !viewModel.qsoManager.lockedDXLocator.isEmpty {
                        Text("(\(viewModel.qsoManager.lockedDXLocator))")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Stop QSO") {
                viewModel.resetQSOState()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.qsoManager.isQSOOngoing())
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
    }
}
