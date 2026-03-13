//
//  ConfigurationView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - Configuration View

struct ConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @Binding var navigationPath: NavigationPath
    
    @State private var showWhatsNew = false
    
    private static let appLogger = AppLogger(category: "APP")
    
    // Focus state
    private enum FocusField {
        case callsign
        case locator
        case frequency
    }
    
    @FocusState private var focusedInput: FocusField?
    @State private var lastFocusedInput: FocusField?
    
    @State private var validCallsign = false
    @State private var validLocator = false
    @State private var activeHelp: HelpTip?
    
    // Editable local state (avoids writing to @AppStorage on every keystroke)
    @State private var callsignText: String = ""
    @State private var locatorText: String = ""
    @State private var frequencyText: String = ""
    @State private var frequencySliderTemp: Double = 1500.0
    @State private var sliderTempValue: Float = 1.0

    private let minGain: Float = 0.1
    private let maxGain: Float = 2.0

    // MARK: - Number formatter (shared static instance)
    private static let frequencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        return f
    }()
    
    // MARK: - Commit helpers
    
    private func commitCallsign() {
        let text = callsignText.uppercased()
        callsignText = text
        validCallsign = isValidCallsign(text)
        
        if validCallsign && !text.isEmpty {
            viewModel.callsign = text
            AnalyticsManager.shared.logConfigurationSaved()
        }
    }
    
    private func commitLocator() {
        var text = locatorText.uppercased()
        text.removeAll(where: { $0.isWhitespace })
        if text.count > 4 { text = String(text.prefix(4)) }
        locatorText = text
        validLocator = isValidLocator(text)
        if validLocator && !text.isEmpty {
            viewModel.locator = text
            AnalyticsManager.shared.logConfigurationSaved()
        }
    }
    
    // MARK: - Commit frequency
    private func commitFrequencyText() {
        let formatter = Self.frequencyFormatter
        if let number = formatter.number(from: frequencyText) {
            let valueHz = min(max(0, number.doubleValue * 1000), 3000)
            viewModel.frequency = valueHz
            frequencySliderTemp = valueHz
            frequencyText = formatter.string(from: NSNumber(value: valueHz / 1000)) ?? frequencyText
            AnalyticsManager.shared.logConfigurationSaved()
        } else {
            frequencyText = formatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? frequencyText
        }
    }

    var body: some View {
        Form {
            // MARK: - Station (inline — critical settings)
            Section {
                Group {
                    callsignView
                    locatorView

                    ToggleRow(
                        labelKey: "Auto (from GPS)",
                        helpTip: .locatorGPS,
                        isOn: Binding(
                            get: { viewModel.autoLocatorFromGPS },
                            set: { viewModel.setAutoLocatorFromGPS($0) }
                        ),
                        activeHelp: $activeHelp
                    )

                    ToggleRow(
                        labelKey: "Include Grid in CQ",
                        helpTip: .cqIncludeGrid,
                        isOn: $viewModel.cqIncludeGrid,
                        activeHelp: $activeHelp
                    )

                    CQModifierView()
                }
                .listRowBackground(Color(.systemGray6))
            } header: {
                Text("Station details")
            }

            // MARK: - Mode & Frequency (inline)
            Section {
                Group {
                    modeView
                    cycleView
                    BandPickerView(
                        selectedBand: $viewModel.selectedBand,
                        isFT4: viewModel.isFT4
                    )
                    frequencyView
                    inputGainView
                }
                .listRowBackground(Color(.systemGray6))
            } header: {
                Text("Mode and frequency")
            }

            // MARK: - QSO → detail screen
            Section {
                NavigationLink(value: ConfigDestination.qso) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("QSO settings")
                        Text("Auto-sequence: \(viewModel.autoSequencingEnabled ? String(localized: "On") : String(localized: "Off"))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color(.systemGray6))
            } header: {
                Text("Transmission and behaviour")
            }

            // MARK: - Interface (inline — single control)
            Section {
                viewModeView
                    .listRowBackground(Color(.systemGray6))
            } header: {
                Text("Interface")
            }

            // MARK: - Support → detail screen
            Section {
                NavigationLink(value: ConfigDestination.support) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Support")
                        Text("User support")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color(.systemGray6))
            } header: {
                Text("Support")
            }

            // MARK: - Privacy (inline)
            Section {
                Group {
                    analyticsSection

                    if flags.isEnabled(.showLogsView) {
                        NavigationLink {
                            LogsView()
                        } label: {
                            Text("View app logs")
                        }
                    }
                }
                .listRowBackground(Color(.systemGray6))
            } header: {
                Text("Privacy & Anonymous Statistics")
            }

            // MARK: - Debug
            #if DEBUG
            Section {
                Group {
                    Button {
                        triggerRatePrompt()
                    } label: {
                        Label("Test Rate Prompt", systemImage: "star.fill")
                    }

                    Button {
                        triggerSharePrompt()
                    } label: {
                        Label("Test Share Prompt", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        triggerDonationPrompt()
                    } label: {
                        Label("Test Donation Prompt", systemImage: "heart.fill")
                    }

                    Button {
                        showWhatsNew = true
                    } label: {
                        Label("Show What's New", systemImage: "sparkles")
                    }

                    Button(role: .destructive) {
                        fatalError("Intentional debug crash for testing crash reporting")
                    } label: {
                        Label("Crash reporter test", systemImage: "exclamationmark.triangle")
                    }
                }
                .listRowBackground(Color(.systemGray6))
            } header: {
                Text("Debug")
            }
            #endif

            // MARK: - About (inline)
            Section {
                Group {
                    LicenseView()
                    versionSection
                    copyrightSection
                }
                .listRowBackground(Color(.systemGray6))
            } header: {
                Text("About")
            }
        }
        .navigationDestination(for: ConfigDestination.self) { destination in
            switch destination {
            case .qso:
                QSOSettingsView()
            case .support:
                SupportDetailView()
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedInput = nil
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            activeHelp = nil
            callsignText = viewModel.callsign
            locatorText = viewModel.locator
            validCallsign = isValidCallsign(viewModel.callsign)
            validLocator = isValidLocator(viewModel.locator)
            frequencyText = Self.frequencyFormatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? ""
            frequencySliderTemp = viewModel.frequency
            sliderTempValue = Float(viewModel.inputGain)
        }
        .onChange(of: focusedInput) { newValue in
            if let lastField = lastFocusedInput, lastField != newValue {
                switch lastField {
                case .callsign:
                    commitCallsign()
                case .locator:
                    commitLocator()
                case .frequency:
                    commitFrequencyText()
                }
            }
            lastFocusedInput = newValue
        }
        .onChange(of: viewModel.frequency) { newValue in
            frequencySliderTemp = newValue
            if focusedInput != .frequency {
                let newText = Self.frequencyFormatter.string(
                    from: NSNumber(value: newValue / 1000)
                ) ?? frequencyText
                if frequencyText != newText {
                    frequencyText = newText
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 50)
        }
        .onChange(of: viewModel.callsign) { newValue in
            if callsignText != newValue {
                callsignText = newValue
            }
            let isValid = isValidCallsign(newValue)
            if validCallsign != isValid {
                validCallsign = isValid
            }
        }
        .onChange(of: viewModel.locator) { newValue in
            if locatorText != newValue {
                locatorText = newValue
            }
            let isValid = isValidLocator(newValue)
            if validLocator != isValid {
                validLocator = isValid
            }
        }
    }
    
    // MARK: - Debug Helpers
    #if DEBUG
    private func triggerRatePrompt() {
        let prompts = InAppPrompts.shared
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            prompts.requestRate()
        }
    }
    
    private func triggerSharePrompt() {
        let prompts = InAppPrompts.shared
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            prompts.showPreShareAlert = true
        }
    }
    
    private func triggerDonationPrompt() {
        let prompts = InAppPrompts.shared
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            prompts.showDonationAlert = true
        }
    }
    #endif
    
    // MARK: - Inline Subviews
    
    private var callsignView: some View {
        CallsignFieldView(
            callsignText: $callsignText,
            validCallsign: $validCallsign,
            onCommit: commitCallsign
        )
        .focused($focusedInput, equals: .callsign)
    }
    
    private var locatorView: some View {
        LocatorFieldView(
            locatorText: $locatorText,
            validLocator: $validLocator,
            disabled: viewModel.autoLocatorFromGPS,
            onCommit: commitLocator
        )
        .focused($focusedInput, equals: .locator)
    }
    
    private var viewModeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("View mode")
            Picker("View mode", selection: Binding(
                get: { viewModel.selectedViewMode },
                set: { newMode in
                    viewModel.selectedViewMode = newMode
                    AnalyticsManager.shared.trackViewMode(newMode)
                }
            )) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.textKey)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text("View mode"))
        }
    }
    
    // MARK: - Mode & Frequency Subviews

    private var modeView: some View {
        HStack {
            Text("Mode:")
            Spacer()
            Picker("Mode", selection: isFT4Binding) {
                Text("FT8").tag(false)
                Text("FT4").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .accessibilityLabel(Text("Radio mode"))
        }
    }

    private var isFT4Binding: Binding<Bool> {
        Binding(
            get: { viewModel.isFT4 },
            set: { newValue in
                Task { @MainActor in
                    viewModel.switchModeWhileRX(isFT4: newValue)
                    AnalyticsManager.shared.trackRadioModeChange(isFT4: newValue)
                    let modeStr = newValue ? "FT4" : "FT8"
                    let cycleStr: String
                    if newValue {
                        cycleStr = viewModel.evenCycle ? "even (0s)" : "odd (7.5s)"
                    } else {
                        cycleStr = viewModel.evenCycle ? "even (0/30s)" : "odd (15/45s)"
                    }
                    Self.appLogger.log(.info, "Mode changed to \(modeStr), current cycle: \(cycleStr)")
                }
            }
        )
    }

    private var cycleView: some View {
        HStack {
            Text("Transmission cycle:")
            Spacer()
            Picker("Cycle", selection: evenCycleBinding) {
                if viewModel.isFT4 {
                    Text("0").tag(true)
                    Text("7.5").tag(false)
                } else {
                    Text("0/30").tag(true)
                    Text("15/45").tag(false)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .accessibilityLabel(Text("TX cycle offset"))
        }
    }

    private var evenCycleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.evenCycle },
            set: { newValue in
                viewModel.evenCycle = newValue
                if viewModel.isFT4 {
                    let offset = newValue ? 0.0 : 7.5
                    Self.appLogger.log(.info, "FT4 cycle changed to \(newValue ? "even" : "odd") — offset: \(offset)s")
                } else {
                    let offset = newValue ? 0.0 : 15.0
                    Self.appLogger.log(.info, "FT8 cycle changed to \(newValue ? "even" : "odd") — offsets: \(offset)/\(offset + 30.0)s")
                }
            }
        )
    }

    private var frequencyView: some View {
        VStack {
            HStack {
                Text("Frequency offset:")
                Spacer()
                HStack(spacing: 0) {
                    TextField("Frequency", text: $frequencyText)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .focused($focusedInput, equals: .frequency)
                        .lineLimit(1)
                        .onSubmit { commitFrequencyText() }
                        .frame(width: 80)
                    Text("kHz")
                        .padding(5)
                }
            }

            HStack {
                Button {
                    viewModel.frequency = max(0, viewModel.frequency - 10)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text("Decrease frequency"))

                Slider(value: $frequencySliderTemp, in: 0.1 ... 3000, step: 10) { isEditing in
                    if !isEditing {
                        viewModel.frequency = frequencySliderTemp
                        frequencyText = Self.frequencyFormatter.string(
                            from: NSNumber(value: frequencySliderTemp / 1000)
                        ) ?? frequencyText
                        AnalyticsManager.shared.logConfigurationSaved()
                    }
                }

                Button {
                    viewModel.frequency = min(3000, viewModel.frequency + 10)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text("Increase frequency"))
            }
        }
    }

    private var inputGainView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Gain:")
                Spacer()
                Text(String(format: "%.2f×", sliderTempValue))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $sliderTempValue,
                in: Float(minGain)...Float(maxGain),
                onEditingChanged: { isEditing in
                    if !isEditing {
                        viewModel.inputGain = Double(sliderTempValue)
                    }
                }
            )
            .tint(.blue)
            .accessibilityValue(Text(String(format: "%.2f times", sliderTempValue)))
        }
    }

    private var analyticsSection: some View {
        ToggleRow(
            labelKey: "Share usage statistics",
            helpTip: .analytics,
            isOn: Binding(
                get: { AnalyticsManager.shared.isAnalyticsEnabled },
                set: { AnalyticsManager.shared.isAnalyticsEnabled = $0 }
            ),
            activeHelp: $activeHelp
        )
    }
    
    private var versionSection: some View {
        VStack(spacing: 4) {
            Text("Version")
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text(String(format: String(localized: "Version %@ (Build %@)"), version, build))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Version unknown")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 2)
    }
    
    private var copyrightSection: some View {
        VStack(spacing: 4) {
            Text(".copyright")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Pablo Turrión San Pedro (EA4IQL)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

#Preview("ConfigurationView") {
    NavigationStack {
        ConfigurationView(navigationPath: .constant(NavigationPath()))
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .environmentObject(
                FT8ViewModel(
                    txMessages: PreviewMocks.txMessages,
                    rxMessages: PreviewMocks.rxMessages
                )
            )
            .environmentObject(FeatureFlagManager.shared)
    }
}
