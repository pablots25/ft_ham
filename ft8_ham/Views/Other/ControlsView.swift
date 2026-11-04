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
    @EnvironmentObject private var flags: FeatureFlagManager
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        // Evaluated once per body (it validates callsign/locator).
        let settingsLoaded = viewModel.settingsLoaded
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
            Button(viewModel.transmitLoopActive ? "Stop Auto TX" : "Start Auto TX") {
                viewModel.toggleTransmit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .tint(viewModel.transmitLoopActive ? .red : .blue)
            .buttonStyle(.borderedProminent)
            .accessibilityShowsLargeContentViewer()
            .disabled(!settingsLoaded)

            if flags.isEnabled(.enableFreeText) {
                Button(viewModel.freeTextLoopActive ? "Stop Free Text" : "Free Text") {
                    if viewModel.freeTextLoopActive {
                        viewModel.stopFreeTextLoop()
                    } else {
                        // Presented by ContentView: see RootUIState.
                        viewModel.rootState.showFreeTextSheet = true
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
                .tint(viewModel.freeTextLoopActive ? .red : .blue)
                .buttonStyle(.borderedProminent)
            .accessibilityShowsLargeContentViewer()
                .disabled(!settingsLoaded)
                .accessibilityIdentifier("button_freeText")
            }

            Button("Stop TX") {
                viewModel.stopCurrentTX()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .tint(viewModel.isTransmitting ? .red : .blue)
            .buttonStyle(.borderedProminent)
            .accessibilityShowsLargeContentViewer()
            .disabled(!settingsLoaded || !viewModel.isTransmitting)

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
            .accessibilityShowsLargeContentViewer()
            .disabled(!settingsLoaded)

            Button("Stop all") {
                viewModel.stopCurrentTX()
                Task { @MainActor in
                    await viewModel.stopSequencer()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .accessibilityShowsLargeContentViewer()
            .disabled(!settingsLoaded || (!viewModel.isListening && !viewModel.isTransmitting && !viewModel.transmitLoopActive && !viewModel.freeTextLoopActive))
            }
            .padding(.horizontal)
            .frame(minWidth: containerWidth, alignment: .center)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { containerWidth = $0 }
            }
        )
        .operatingChromeTypeSize()
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
    @EnvironmentObject private var flags: FeatureFlagManager
    @State private var showGenMessages = false
    @State private var sheetDetent: PresentationDetent = .large
    @State private var stationSettingsExpanded = false
    @State private var genMessagesExpanded = false

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
                    SelectedTXMessageField(message: viewModel.allMessages[index])
                } else {
                    SelectedTXMessageField(message: "")
                }
                
                
                if !viewModel.autoSequencingEnabled {
                    Button(">") {
                        if let index = viewModel.selectedMessageIndex {
                            viewModel.selectedMessageIndex = (index + 1) % viewModel.allMessages.count
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if flags.isEnabled(.controlsSheet) {
                    Button {
                        showGenMessages = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityShowsLargeContentViewer()
                }
            }
        }
        // Capped before the sheet so the Quick config sheet keeps full size.
        .operatingChromeTypeSize()
        .sheet(isPresented: $showGenMessages) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        
                        
                        DisclosureGroup(isExpanded: $stationSettingsExpanded) {
                            StationSettingsContent()
                        } label: {
                            Text("Station Settings")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        BandPickerView(
                            selectedBand: $viewModel.selectedBand,
                            isFT4: viewModel.isFT4,
                            customDialFrequencyHz: $viewModel.customDialFrequencyHz
                        )

                        Divider()

                        DisclosureGroup(isExpanded: $genMessagesExpanded) {
                            GenMessagesView()
                        } label: {
                            Text("Quick message generation")
                            .   font(.headline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

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
                    .padding(.horizontal, 20)
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

// MARK: - Selected TX message

/// Read-only display of the message the next slot will transmit.
///
/// A disabled `TextField` clipped the tail of long messages without an
/// ellipsis, so "CQ SOTA VE7ZAX CN89" read as "... CN8" on a phone even though
/// the full grid went on the air. The text shrinks to fit instead, so the
/// operator always sees exactly what is sent.
struct SelectedTXMessageField: View {
    let message: String

    var body: some View {
        Text(message.isEmpty ? " " : message)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScaleFactor)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Next message"))
            .accessibilityValue(Text(message))
    }

    /// Low enough for the longest generated message (a modifier CQ with an
    /// 11-character compound call) to fit between the selector buttons.
    static let minimumScaleFactor: CGFloat = 0.5
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
        } else if viewModel.freeTextLoopActive {
            String(localized: "Free Text TX")
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
        } else if viewModel.transmitLoopActive || viewModel.freeTextLoopActive {
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
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .operatingChromeTypeSize()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Clock View

struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            // Show the SNTP-corrected clock, which is what the slots follow.
            let currentUTC = DateFormatter.utcFormatterClock.string(from: AppClock.corrected(context.date))

            HStack(spacing: 6) {
                Text("UTC: \(currentUTC)")
                    .foregroundStyle(.gray)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ClockOffsetChip()
            }
            .operatingChromeTypeSize()
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


/// How much room the QSO strip gets. Chosen by the caller rather than
/// measured, so the strip does not change shape as the status text changes.
enum QSOStripDensity {
    /// Portrait and wide layouts: the Log QSO button shows its title.
    case regular
    /// Narrow columns, such as the condensed landscape grid: icons only.
    case compact
}

struct QSOStatusView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    var density: QSOStripDensity = .regular

    /// The status never wraps, in any density.
    static let statusLineLimit = 1
    /// Low enough for the longest status with an 11-character compound call.
    static let statusMinimumScaleFactor: CGFloat = 0.4

    /// Stop QSO turns red while a QSO is running, so the way out is obvious.
    static func stopQSOTint(isQSOOngoing: Bool) -> Color {
        isQSOOngoing ? .red : .secondary
    }

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

    // MARK: - CAT status indicator
    private var catStatusColor: Color {
        if !viewModel.catStatusOK { return .red }
        return viewModel.catConnected ? .green : .orange
    }

    private var catStatusHelp: String {
        if let error = viewModel.catLastError, !viewModel.catStatusOK {
            return "CAT error: \(error)"
        }
        return viewModel.catConnected ? "CAT connected" : "CAT not connected — check rigctld host/port"
    }

    @ViewBuilder
    private var catStatusChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption2)
            Text("CAT")
                .font(.caption2)
        }
        .foregroundStyle(catStatusColor)
        .fixedSize(horizontal: true, vertical: false)
        .help(catStatusHelp)
        .accessibilityLabel(catStatusHelp)
    }
    
    private var displayedRetryCount: Int {
        min(viewModel.qsoManager.retryCounter, viewModel.qsoManager.maxRetrySlots)
    }
    
    // MARK: - QSO actions

    /// Log QSO is the rescue action for a QSO the sequencer did not finish,
    /// so it gets the prominent button. Stop is a small secondary icon.
    private var qsoActions: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.forceLogCurrentQSO()
            } label: {
                Label("Log QSO", systemImage: "book")
            }
            .modifier(QSOStripLabelStyle(density: density))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.qsoManager.isQSOOngoing())
            .accessibilityIdentifier("button_forceLogQSO")

            Button {
                viewModel.resetQSOState()
            } label: {
                Label("Stop QSO", systemImage: "xmark.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .tint(Self.stopQSOTint(isQSOOngoing: viewModel.qsoManager.isQSOOngoing()))
            .disabled(!viewModel.qsoManager.isQSOOngoing())
            .accessibilityLabel("Stop QSO")
            .accessibilityIdentifier("button_stopQSO")
        }
    }

    var body: some View {
        HStack {
            VStack(spacing: 2) {
                
                // Status + (x/y)
                HStack(spacing: 4) {
                    // Always one line: a long status such as "Sending locator
                    // to EA4XXX" shrinks instead of wrapping, so the strip
                    // keeps its height while the QSO advances.
                    Text(viewModel.qsoManager.qsoState.localizedStatus)
                        .foregroundStyle(statusColor)
                        .lineLimit(Self.statusLineLimit)
                        .minimumScaleFactor(Self.statusMinimumScaleFactor)
                        .allowsTightening(true)
                        .layoutPriority(1)
                    
                    if shouldShowRetry {
                        Text("(\(displayedRetryCount)/\(viewModel.qsoManager.maxRetrySlots))")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer(minLength: 0)

                    if viewModel.catEnabled {
                        catStatusChip
                    }

                    if viewModel.bandHopEnabled, viewModel.bandHopState != .stopped {
                        BandHopChip()
                    }
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
            
            qsoActions
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .operatingChromeTypeSize()
    }
}

/// Title only in regular density, icon only in compact. VoiceOver reads
/// the title either way.
private struct QSOStripLabelStyle: ViewModifier {
    let density: QSOStripDensity

    func body(content: Content) -> some View {
        switch density {
        case .regular: content.labelStyle(.titleOnly)
        case .compact: content.labelStyle(.iconOnly)
        }
    }
}

// MARK: - Clock offset chip

/// Shows how far the device clock is from SNTP time. Hidden while the
/// correction is negligible; orange up to 1 s, red beyond (FT8 needs < 1 s).
struct ClockOffsetChip: View {
    @ObservedObject private var clockSync = ClockSyncManager.shared

    var body: some View {
        if clockSync.isEnabled, abs(clockSync.offset) >= 0.3 || clockSync.lastError != nil {
            HStack(spacing: 2) {
                Image(systemName: clockSync.lastError == nil ? "clock.badge.checkmark" : "clock.badge.exclamationmark")
                    .font(.caption2)
                if clockSync.lastError == nil {
                    Text("Δ\(String(format: "%+.1f", clockSync.offset))s")
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
            .help(helpText)
            .accessibilityLabel(helpText)
            .accessibilityIdentifier("chip_clockOffset")
        }
    }

    private var color: Color {
        if clockSync.lastError != nil { return .secondary }
        return clockSync.isWarning ? .red : .orange
    }

    private var helpText: String {
        if clockSync.lastError != nil {
            return String(localized: "Clock sync failed, using the device clock")
        }
        return String(
            format: String(localized: "Device clock is off by %@ s. FT8 needs less than 1 s"),
            String(format: "%+.2f", clockSync.offset)
        )
    }
}

// MARK: - Band hop chip

/// "HOP 20m 3:41" countdown to the next band; paused during a QSO. Tap to
/// hop right away.
struct BandHopChip: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button {
                viewModel.skipToNextBand()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                    Text(label(at: context.date))
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(color)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Band Hopping"))
            .accessibilityIdentifier("chip_bandHop")
        }
    }

    private func label(at now: Date) -> String {
        switch viewModel.bandHopState {
        case .stopped:
            return ""
        case .dwelling(let band, let until):
            return "\(band) \(Self.mmss(until.timeIntervalSince(now)))"
        case .paused(let band, _):
            return "\(band) ⏸"
        }
    }

    private var color: Color {
        if case .paused = viewModel.bandHopState { return .orange }
        return .mint
    }

    private static func mmss(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
