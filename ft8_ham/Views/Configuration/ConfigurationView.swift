//
//  ConfigurationView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI
import SafariServices

// MARK: - New Configuration View (Settings-style)

struct NewConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @Binding var shouldScrollToDonations: Bool

    @State private var showHelp = false
    @State private var showSupport = false

    var body: some View {
        List {
            Group{
                // MARK: - Settings
                Section {
                    NavigationLink {
                        StationSettingsView()
                    } label: {
                        Label("Station", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    
                    NavigationLink {
                        RadioSettingsView()
                    } label: {
                        Label("Radio", systemImage: "dial.low")
                    }
                    
                    NavigationLink {
                        BehaviorSettingsView()
                    } label: {
                        Label("Behavior", systemImage: "gearshape.2")
                    }
                    
                    NavigationLink {
                        InterfaceSettingsView()
                    } label: {
                        Label("Interface", systemImage: "rectangle.3.group")
                    }

                    NavigationLink {
                        #if canImport(FTHamPremium)
                        CatSettingsView()
                        #else
                        CatSettingsViewStub()
                        #endif
                    } label: {
                        Label("CAT Control", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                
                // MARK: - Debug
#if DEBUG
                Section {
                    NavigationLink {
                        DebugSettingsView()
                    } label: {
                        Label("Debug", systemImage: "ladybug")
                    }
                }
#endif
                
                // MARK: - Help & Support
                Section {
                    Button {
                        showHelp = true
                    } label: {
                        HStack {
                            Label("Getting Started Guide", systemImage: "book")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Button {
                        showSupport = true
                    } label: {
                        HStack {
                            Label("Support Development", systemImage: "heart")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Button {
                        if let url = URL(string: "mailto:ftham@turrion.dev?subject=FT8%20Ham%20App%20Feedback") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("Send Feedback", systemImage: "envelope")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Help & Support")
                }
                
                // MARK: - About
                Section {
                    NavigationLink {
                        LegalAndPrivacyView()
                    } label: {
                        Label("Legal & Privacy", systemImage: "hand.raised")
                    }
                } footer: {
                    versionFooter
                }
            }
            .padding(.horizontal)
        }
        .listStyle(.plain)
        .sheet(isPresented: $showSupport) {
            NavigationStack {
                SupportView()
                    .navigationTitle("Support Development")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSupport = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showHelp) {
            SafariView(url: URL(string: "https://ftham.turrion.dev/#getting-started")!)
                .ignoresSafeArea()
        }
        .onChange(of: shouldScrollToDonations) { shouldScroll in
            if shouldScroll {
                showSupport = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    shouldScrollToDonations = false
                }
            }
        }
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        VStack(spacing: 2) {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text(String(format: String(localized: "Version %@ (Build %@)"), version, build))
            } else {
                Text("Version unknown")
            }
            Text(".copyright")
            Text("Pablo Turrión San Pedro (EA4IQL)")
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .font(.footnote)

    }

}

// MARK: - Legacy Configuration View

struct ConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @Binding var navigationPath: NavigationPath
    @Binding var shouldScrollToDonations: Bool

    @State private var showWhatsNew = false
    @State private var showHelp = false
    
    private static let appLogger = AppLogger(category: "APP")
    
    // Focus state
    private enum FocusField {
        case callsign
        case locator
        case frequency
        case retries
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: Configuration fields
                    
                    Text("Station details").font(.headline)
                    
                    callsignView
                        .padding(.horizontal)
                    
                    Divider()

                    locatorView
                        .padding(.horizontal)
                    
                    Divider()
                    
                    CQModifierView()
                        .padding(.horizontal)
                    
                    Divider()
                    
                    Text("Mode and frequency").font(.headline)
                    
                    HStack(spacing: 20) {
                        modeView
                        cycleView
                    }
                    
                    BandPickerView(
                        selectedBand: $viewModel.selectedBand,
                        isFT4: viewModel.isFT4
                    )
                    
                    frequencyView
                    inputGainView
        
                    Divider()
                    
                    Text("QSO settings").font(.headline)
                    
                    qsoConfigSection
                    
                    togglesView
                    
                    Divider()
                    
                    Text("Interface").font(.headline)
                    
                    viewModeView
                    
                    Divider()
                    
                    Text("Messages").font(.headline)
                    
                    GenMessagesView()
                    
                    Divider()
                    
                    Text("User support").font(.headline)
                    
                    Button {
                        showHelp = true
                    } label: {
                        Text("Help")
                            .font(.headline)
                    }
                    
                    Button("Reset help messages") {
                        AppStorageResetter.resetTutorials()
                    }
                    Button("Show initial tutorial") {
                        AppStorageResetter.resetOnboarding()
                    }
                    
                    Divider()
                    
                    SupportView()
                        .id("donations") // Add ID for scrolling
                    
                    Divider()
                    
                    ContactView()
                    
                    Divider()
                    
                    Text("Privacy and analytics").font(.headline)
                    
                    analyticsSection
                            
                    if flags.isEnabled(.showLogsView) {
                        NavigationLink {
                            LogsView()
                        } label: {
                            Text("View app logs")
                        }
                    }
                

                #if DEBUG
                Divider()
                Text("Debug").font(.headline)
                Group {
                    Button {
                        triggerRatePrompt()
                    } label: {
                        Label(String(localized: "Test Rate Prompt"), systemImage: "star.fill")
                    }
                    
                    Button {
                        triggerSharePrompt()
                    } label: {
                        Label(String(localized: "Test Share Prompt"), systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        triggerDonationPrompt()
                    } label: {
                        Label(String(localized: "Test Donation Prompt"), systemImage: "heart.fill")
                    }
                    
                    Button {
                        showWhatsNew = true
                    } label: {
                        Label(String(localized: "Show What's New"), systemImage: "sparkles")
                    }
                    
                    Button(role: .destructive) {
                        fatalError(String(localized: "Intentional debug crash for testing crash reporting"))
                    } label: {
                        Label(String(localized: "Crash reporter test"), systemImage: "exclamationmark.triangle")
                    }
                }
                #endif

                
                Divider()
                    
                Text("Legal").font(.headline)
                
                LicenseView()
                
                versionSection
                
                copyrightSection
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showHelp) {
            SafariView(
                url: URL(string: "https://ftham.turrion.dev/#getting-started")!
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            activeHelp = nil
        }
        .onChange(of: shouldScrollToDonations) { shouldScroll in
            if shouldScroll {
                withAnimation {
                    proxy.scrollTo("donations", anchor: .top)
                }
                // Reset the flag after scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    shouldScrollToDonations = false
                }
            }
        }
        
        // Commit on focus change
        .onChange(of: focusedInput) { newValue in
            // Only commit if we're leaving a field (not entering one)
            if let lastField = lastFocusedInput, lastField != newValue {
                switch lastField {
                case .callsign:
                    commitCallsign()
                case .locator:
                    commitLocator()
                case .frequency:
                    commitFrequencyText()
                case .retries:
                    break
                }
            }
            lastFocusedInput = newValue
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 50)
        }
        .onAppear {
            callsignText = viewModel.callsign
            validCallsign = isValidCallsign(viewModel.callsign)
            validLocator = isValidLocator(viewModel.locator)
            
            frequencyText = Self.frequencyFormatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? ""
        }
        .onChange(of: viewModel.callsign) { newValue in
            let isValid = isValidCallsign(newValue)
            if validCallsign != isValid {
                validCallsign = isValid
            }
            if isValid && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
        .onChange(of: viewModel.locator) { newValue in
            let isValid = isValidLocator(newValue)
            if validLocator != isValid {
                validLocator = isValid
            }
            if isValid && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
        .onChange(of: viewModel.frequency) { newValue in
            if focusedInput != .frequency {
                let newText = Self.frequencyFormatter.string(
                    from: NSNumber(value: newValue / 1000)
                ) ?? frequencyText
                if frequencyText != newText {
                    frequencyText = newText
                }
            }
            if newValue > 0 {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
        } // Close ScrollViewReader
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
    
    // MARK: - Subviews
    private var callsignView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Callsign:")
                TextField("", text: $callsignText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .focused($focusedInput, equals: .callsign)
                    .lineLimit(1)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: callsignText) { newValue in
                        validCallsign = isValidCallsign(newValue.uppercased())
                    }
                    .onSubmit {
                        commitCallsign()
                    }
                    .border(validCallsign ? Color.clear : Color.red)
            }

            Text("Callsign modifiers are allowed")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
    
    private var locatorView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Locator:")
                Spacer()
                TextField("", text: $viewModel.locator)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .focused($focusedInput, equals: .locator)
                    .lineLimit(1)
                    .disabled(viewModel.autoLocatorFromGPS)
                    .onChange(of: viewModel.locator) { newValue in
                        var text = newValue.uppercased()
                        text.removeAll(where: { $0.isWhitespace })
                        if text.count > 4 {
                            text = String(text.prefix(4))
                        }
                        if text != viewModel.locator {
                            viewModel.locator = text
                        }
                        validLocator = isValidLocator(text)
                    }
                    .border(validLocator ? Color.clear : Color.red)
            }
            
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
        }
        .padding(.horizontal, 20)
    }
    
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
                HelpIconButton(helpHint: HelpTip.audioFrequencyHz.accessibilityHint) {
                    activeHelp = (activeHelp == .audioFrequencyHz) ? nil : .audioFrequencyHz
                }
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

            if activeHelp == .audioFrequencyHz {
                HelpBubble(text: HelpTip.audioFrequencyHz.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
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
            }
            .padding(.horizontal, 40)
        }
    }
    
    private var viewModeView: some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        
        // Available view modes based on device and feature flags
        let availableModes = ViewMode.allCases.filter { mode in
            // Dashboard: in DEBUG always show (any device) if flag enabled, in RELEASE only on iPad if flag enabled
            if mode == .dashboard {
                #if DEBUG
                return flags.isEnabled(.enableIpadDashboard)
                #else
                return isIPad && flags.isEnabled(.enableIpadDashboard)
                #endif
            }
            
            // Other iPad-only modes just require iPad device
            if mode.isIPadOnly {
                return isIPad
            }
            
            return true
        }
        
        return VStack {
            Text(String(localized: "View mode:"))
            Picker(String(localized: "View mode"), selection: Binding(
                get: { viewModel.selectedViewMode },
                set: { newMode in
                    viewModel.selectedViewMode = newMode
                    AnalyticsManager.shared.trackViewMode(newMode)
                }
            )) {
                ForEach(availableModes) { mode in
                    Text(mode.textKey)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
        }
    }
    
    private var inputGainView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Gain:")
                HelpIconButton(helpHint: HelpTip.audioGain.accessibilityHint) {
                    activeHelp = (activeHelp == .audioGain) ? nil : .audioGain
                }
                Spacer()
                Text(String(format: "%.2f×", sliderTempValue))
                    .foregroundStyle(.secondary)
            }

            if activeHelp == .audioGain {
                HelpBubble(text: HelpTip.audioGain.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
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
            .accentColor(.blue)
            .onAppear {
                sliderTempValue = Float(viewModel.inputGain)
            }
        }
        .padding(.horizontal, 40)
    }

    private var togglesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(
                labelKey: "Auto RX at start",
                helpTip: .autoRXAtStart,
                isOn: $viewModel.autoRXAtStart,
                activeHelp: $activeHelp
            )
            
            ToggleRow(
                labelKey: "Reply to CQ received",
                helpTip: .autoCQReply,
                isOn: $viewModel.autoCQReplyEnabled,
                activeHelp: $activeHelp
            )

            ToggleRow(
                labelKey: "Only if new band/mode",
                helpTip: .autoCQNewBandMode,
                isOn: $viewModel.autoCQReplyOnlyNewBandMode,
                activeHelp: $activeHelp
            )
            
            ToggleRow(
                labelKey: "Show TX messages in RX list",
                helpTip: .decodeSelfTX,
                isOn: $viewModel.decodeSelfTXMessages,
                activeHelp: $activeHelp
            )
            
            ToggleRow(
                labelKey: "Hold TX frequency",
                helpTip: .holdTXFrequency,
                isOn: $viewModel.holdTXFrequency,
                activeHelp: $activeHelp
            )
        }
        .padding(.horizontal)
    }

    private var qsoConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(
                labelKey: "Auto-sequence",
                helpTip: .autoSequencing,
                isOn: $viewModel.autoSequencingEnabled,
                activeHelp: $activeHelp
            )
            
            HStack(spacing: 6) {
                TextField(String(localized: "Retries"), value: $viewModel.maxRetrySlots, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .focused($focusedInput, equals: .retries)
                    .lineLimit(1)
                    .frame(width: 50)
                Text(String(localized: "Retries"))
                    .font(.body)
                    .accessibilityLabel(Text(String(localized: "Retransmission retries")))
                    .accessibilityHint(Text(String(localized: "Number of times to resend messages if not acknowledged")))
            }
            
            ToggleRow(
                labelKey: "Auto QSO logging",
                helpTip: .autoQSOLogging,
                isOn: $viewModel.autoQSOLogging,
                activeHelp: $activeHelp
            )
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
            Text(String(localized: "Version"))
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text(String(format: String(localized: "Version %@ (Build %@)"), version, build))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Version unknown"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 2)
    }
    
    private var copyrightSection: some View {
        VStack(spacing: 4) {
            Text(String(localized: ".copyright"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(String(localized: "Pablo Turrión San Pedro (EA4IQL)"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

#Preview("ConfigurationView") {
    NavigationStack {
        ConfigurationView(
            navigationPath: .constant(NavigationPath()),
            shouldScrollToDonations: .constant(false)
        )
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(
        FT8ViewModel(
            txMessages: PreviewMocks.txMessages,
            rxMessages: PreviewMocks.rxMessages
        )
    )
    .environmentObject(FeatureFlagManager.shared)
}
