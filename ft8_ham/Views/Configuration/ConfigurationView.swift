//
//  ConfigurationView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - New Configuration View (Settings-style)

struct NewConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @StateObject private var premiumManager = PremiumManager.shared
    @Binding var shouldScrollToDonations: Bool

    @State private var showHelp = false
    @State private var showSupport = false
    @State private var showPremium = false

    var body: some View {
        List {
            Group {
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
                    
                    #if canImport(FTHamPremium)
                    if premiumManager.isPremiumUnlocked {

                        NavigationLink {
                            CatSettingsView(initialFrequencyMHz: viewModel.catDialFrequencyMHz)
                        } label: {
                            Label("CAT Control", systemImage: "dot.radiowaves.left.and.right")
                        }
   
                    }
                    #endif
                }
                
                // MARK: - Debug
                #if DEBUG
                Section {
                    NavigationLink {
                        DebugSettingsView()
                    } label: {
                        Label("Toggles", systemImage: "ladybug")
                    }
                    
                    Button {
                        showSupport = true
                    } label: {
                        HStack {
                            Label("Support FT HAM", systemImage: "heart")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                } header: {
                    Text("Debug")
                }
                

                #endif
                
                // MARK: - Help & Support
                Section {
                    Button {
                        showHelp = true
                    } label: {
                        HStack {
                            Label("Getting Started", systemImage: "book")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Button {
                        showPremium = true
                    } label: {
                        HStack {
                            Label("Become premium", systemImage: "star")
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
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Support")
                }
                
                // MARK: - About
                Section {
                    NavigationLink {
                        LegalAndPrivacyView()
                    } label: {
                        Label("Legal & Licenses", systemImage: "hand.raised")
                            .tint(.blue)
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
                    .navigationTitle("Support FT HAM")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSupport = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPremium) {
            NavigationStack {
                PremiumPaywallView(premiumManager: PremiumManager.shared, source: "configuration")
                    .navigationTitle("Become Premium")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPremium = false }
                        }
                    }
            }
            .presentationDetents([.large])
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

    private var versionFooter: some View {
        VStack(spacing: 4) {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text(String(format: String(localized: "Version %@ (Build %@)"), version, build))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 8)
    }
}

// MARK: - Configuration View

struct ConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var navigationPath: NavigationPath
    @Binding var shouldScrollToDonations: Bool

    @State private var showWhatsNew = false
    @State private var showHelp = false
    @State private var showMessagesSection = false
    @State private var sliderTempValue: Float = 1.0
    @State private var frequencySliderTemp: Double = 1500.0
    #if DEBUG
    @AppStorage("debugUseNewConfigView") private var debugUseNewConfigView: Bool = true
    #endif
    
    private static let appLogger = AppLogger(category: "APP")
    
    // Focus state
    private enum FocusField {
        case callsign
        case locator
        case frequency
        case retries
        case customDialFrequency
    }
    
    @FocusState private var focusedInput: FocusField?
    @State private var lastFocusedInput: FocusField?
    
    @State private var validCallsign = false
    @State private var validLocator = false
    @State private var activeHelp: HelpTip?
    
    private let minGain: Float = 0.1
    private let maxGain: Float = 2.0
    
    // Editable local state (avoids writing to @AppStorage on every keystroke)
    @State private var callsignText: String = ""
    @State private var locatorText: String = ""
    @State private var frequencyText: String = ""
    @State private var customDialFrequencyText: String = ""
    
    // CQ modifier state - stored in AppStorage, managed by CQModifierView
    
    // Type-safe computed property for reading CQ modifier from AppStorage
    private var cqModifier: CQModifier {
        let raw = UserDefaults.standard.string(forKey: "cqModifier") ?? CQModifier.none.rawValue
        return CQModifier(rawValue: raw) ?? .none
    }
    
    // Available view modes filtered by device and feature flags
    private var availableModes: [ViewMode] {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        return ViewMode.allCases.filter { mode in
            if mode == .dashboard {
                #if DEBUG
                return flags.isEnabled(.enableIpadDashboard)
                #else
                return isIPad && flags.isEnabled(.enableIpadDashboard)
                #endif
            }
            if mode.isIPadOnly {
                return isIPad
            }
            return true
        }
    }
    
    // MARK: - Number formatter for frequency input
    // ⚠️ Unit consistency: All frequency values are stored in Hz internally.
    // TextField displays/accepts kHz (user-facing).
    // Slider range: 0.1 ... 3000 Hz (= 3 kHz max)
    // Conversion: kHz input × 1000 = Hz stored
    
    private static let frequencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    private static let dialFrequencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 6
        return formatter
    }()
    
    // MARK: - Frequency parsing
    
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

    /// Parses and validates the custom dial frequency text (entered in MHz).
    private func commitCustomDialFrequency() {
        let formatter = Self.dialFrequencyFormatter
        if let number = formatter.number(from: customDialFrequencyText), number.doubleValue > 0 {
            viewModel.customDialFrequencyHz = number.doubleValue * 1_000_000
            customDialFrequencyText = formatter.string(from: NSNumber(value: number.doubleValue)) ?? customDialFrequencyText
        } else {
            customDialFrequencyText = formatter.string(
                from: NSNumber(value: viewModel.customDialFrequencyHz / 1_000_000)
            ) ?? customDialFrequencyText
        }
    }
    
    private func commitCallsign() {
        let text = callsignText.uppercased()
        callsignText = text
        validCallsign = isValidCallsign(text)
        
        if validCallsign {
            viewModel.callsign = text
        }
    }
    
    private func commitLocator() {
        let text = viewModel.locator.uppercased()
        validLocator = isValidLocator(text)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: Configuration fields
                    
                    Text("Station details").font(.headline)
                    
                    callsignView
                    
                    Divider()

                    locatorView
                    
                    Divider()
                    
                    CQModifierView()
                    
                    Divider()
                    
                    Text("Mode and frequency").font(.headline)
                    
                    HStack(spacing: 20) {
                        modeView
                        cycleView
                    }
                    .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
                    
                    Divider()
                    
                    BandPickerView(
                        selectedBand: $viewModel.selectedBand,
                        isFT4: viewModel.isFT4,
                        customDialFrequencyHz: $viewModel.customDialFrequencyHz
                    )
                    
                    frequencyView
                    
                    inputGainView
        
                    Divider()
                    
                    Text("QSO settings").font(.headline)
                    
                    qsoConfigSection
                    
                    Divider()
                    
                    togglesView
                    
                    Divider()
                    
                    Text("Interface").font(.headline)
                    
                    viewModeView
                    
                    Divider()

                    VStack(alignment: .center, spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showMessagesSection.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Messages")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(showMessagesSection ? 90 : 0))
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showMessagesSection {
                            GenMessagesView()
                                .padding(.top, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
                    .clipped()

                    Divider()
                    
                    Text("Support FT HAM").font(.headline)
                    SupportView()
                        .id("donations")
                    
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
                    
                    ContactView()
                    
                    Divider()
                    
                    Text("Privacy & Anonymous Statistics").font(.headline)
                    
                    analyticsSection
                            
                    if flags.isEnabled(.showLogsView) {
                        NavigationLink(destination: LogsView()) {
                            Text("View app logs")
                                .foregroundStyle(.blue)
                        }
                    }
                
                    #if DEBUG
                    Divider()
                    
                    Text("Debug").font(.headline)
                    
                    Section {
                        Toggle("Use new config view", isOn: $debugUseNewConfigView)

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
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedInput = nil
                }
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
                    case .customDialFrequency:
                        commitCustomDialFrequency()
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

                customDialFrequencyText = Self.dialFrequencyFormatter.string(
                    from: NSNumber(value: viewModel.customDialFrequencyHz / 1_000_000)
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
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(.horizontal, horizontalSizeClass == .compact ? 20 : 0)
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
    }
    
    private var locatorView: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(.horizontal, horizontalSizeClass == .compact ? 20 : 0)
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
    }
    
    private var modeView: some View {
        VStack(spacing: 6) {
            Text("Mode:")
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
        VStack(spacing: 6) {
            Text("Transmission cycle:")
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
        VStack(spacing: 10) {
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
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 20 : 0)
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
    }
    
    private var viewModeView: some View {
        VStack(spacing: 6) {
            Text("View mode:")
            Picker("View mode", selection: Binding(
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
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 10 : 0)
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
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
        .padding(.horizontal, horizontalSizeClass == .compact ? 20 : 0)
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
    }

    private var togglesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ToggleRow(
                labelKey: "Auto RX at start",
                helpTip: .autoRXAtStart,
                isOn: $viewModel.autoRXAtStart,
                activeHelp: $activeHelp
            )

            ToggleRow(
                labelKey: "Hold TX frequency",
                helpTip: .holdTXFrequency,
                isOn: $viewModel.holdTXFrequency,
                activeHelp: $activeHelp
            )

            ToggleRow(
                labelKey: "Show TX messages in RX list",
                helpTip: .decodeSelfTX,
                isOn: $viewModel.decodeSelfTXMessages,
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
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 0)
    }

    private var qsoConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(.horizontal)
    }
    
    private var analyticsSection: some View {
        VStack(alignment: .center, spacing: 8) {
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { AnalyticsManager.shared.isAnalyticsEnabled },
                            set: { AnalyticsManager.shared.isAnalyticsEnabled = $0 }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(Text("Share usage statistics"))
                        .accessibilityHint(Text(HelpTip.analytics.accessibilityHint))
                        
                        Text("Share usage statistics")
                            .font(.body)
                        Spacer()
                        
                        // Info button: toggle inline expandable help
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
                                activeHelp = (activeHelp == .analytics) ? nil : .analytics
                            }
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20, height: 20)
                        .accessibilityLabel(Text("Help"))
                        .accessibilityHint(Text(HelpTip.analytics.accessibilityHint))
                    }
                    .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
                    
                    // Inline expandable help with smooth spring animation
                    if activeHelp == .analytics {
                        HelpBubble(text: HelpTip.analytics.text)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                            ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 0)
        }
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
