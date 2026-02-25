//
//  ConfigurationView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI
import SafariServices

// MARK: - In-app Safari View

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor.systemBlue
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - HelpTip Enum (Fallback for iOS 16)

enum HelpTip: Identifiable {
    case autoRXAtStart
    case autoCQReply
    case autoCQNewBandMode
    case decodeSelfTX
    case holdTXFrequency
    case autoSequencing
    case autoQSOLogging
    case analytics

    var id: Self { self }

    var text: String {
        switch self {
        case .autoRXAtStart:
            return String(localized: "Auto RX help")
        case .autoCQReply:
            return String(localized: "Auto CQ Reply help")
        case .autoCQNewBandMode:
            return String(localized: "Auto CQ New Band Mode help")
        case .decodeSelfTX:
            return String(localized: "Decode Self TX help")
        case .holdTXFrequency:
            return String(localized: "Hold TX Frequency help")
        case .autoSequencing:
            return String(localized: "Auto Sequencing help")
        case .autoQSOLogging:
            return String(localized: "Auto QSO Logging help")
        case .analytics:
            return String(localized: "Analytics help")
        }
    }
    
    var accessibilityHint: String {
        text
    }
}

// MARK: - Toggle Row Component

struct ToggleRow: View, Equatable {
    let labelKey: LocalizedStringKey
    let helpTip: HelpTip
    @Binding var isOn: Bool
    @Binding var activeHelp: HelpTip?
    
    static func == (lhs: ToggleRow, rhs: ToggleRow) -> Bool {
        lhs.labelKey == rhs.labelKey &&
        lhs.helpTip == rhs.helpTip &&
        lhs.isOn == rhs.isOn &&
        lhs.activeHelp == rhs.activeHelp
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .accessibilityLabel(Text(labelKey))
                    .accessibilityHint(Text(helpTip.accessibilityHint))
                
                Text(labelKey)
                    .font(.body)
                    .lineLimit(2)
                
                Spacer()
                
                // Info button: toggle inline expandable help
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
                        activeHelp = (activeHelp == helpTip) ? nil : helpTip
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .accessibilityLabel(Text("Help"))
                .accessibilityHint(Text(helpTip.accessibilityHint))
            }
            
            // Inline expandable help with smooth spring animation
            if activeHelp == helpTip {
                HelpBubble(text: helpTip.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
    }
}

private struct HelpBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

// MARK: - Configuration View

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case vertical = "Vertical"
    case separated = "TX/RX Separated"
    case condensed = "Condensed"

    var id: String { rawValue }

    var textKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

struct ConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var showHelp = false
    @State private var showWhatsNew = false
    @State private var sliderTempValue: Float = 1.0
    
    private let appLogger = AppLogger(category: "APP")
    
    // New typed focus state
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
    
    private let minGain: Float = 0.1
    private let maxGain: Float = 2.0
    
    // Editable local state
    @State private var callsignText: String = ""
    @State private var frequencyText: String = ""
    
    // CQ modifier state - stored in AppStorage, managed by CQModifierView
    
    // Type-safe computed property for reading CQ modifier from AppStorage
    private var cqModifier: CQModifier {
        let raw = UserDefaults.standard.string(forKey: "cqModifier") ?? CQModifier.none.rawValue
        return CQModifier(rawValue: raw) ?? .none
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
    
    // MARK: - Frequency parsing
    
    private func commitFrequencyText() {
        let formatter = Self.frequencyFormatter
        
        if let number = formatter.number(from: frequencyText) {
            // Convert kHz (user input) to Hz (internal storage), clamped to 3000 Hz (3 kHz max)
            let valueHz = min(max(0, number.doubleValue * 1000), 3000)
            viewModel.frequency = valueHz
            frequencyText = formatter.string(from: NSNumber(value: valueHz / 1000)) ?? frequencyText
        } else {
            // Revert to current model value if parsing fails
            frequencyText = formatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? frequencyText
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
        ScrollView {
            VStack(spacing: 20) {
                // MARK: Configuration fields
                
                VStack(spacing: 0) {
                    HStack(spacing: 50) {
                        callsignView
                        locatorView
                    }
                    .padding(.bottom, 5)
                    
                    Text("Callsign modifiers are allowed")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                
                CQModifierView()
                
                Divider()
                
                HStack(spacing: 20) {
                    modeView
                    cycleView
                }
                
                bandView
                
                frequencyView
                
                inputGainView
    
                Divider()
                
                qsoConfigSection
                
                togglesView
                
                Divider()
                
                viewModeView
                
                Divider()
                GenMessagesView()
                
                Divider()
                
                Button {
                    showHelp = true
                } label: {
                    Text("Help")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
                
                Button("Reset help messages") {
                    AppStorageResetter.resetTutorials()
                }
                Button("Show initial tutorial") {
                    AppStorageResetter.resetOnboarding()
                }
                
                Divider()
                
                SupportView()
                
                Divider()
                
                ContactView()
                
                Divider()
                
                analyticsSection
                            
                if flags.isEnabled(.showLogsView) {
                    NavigationLink(destination: LogsView()) {
                        Text("View app logs")
                            .foregroundStyle(.blue)
                    }
                }
                

                #if DEBUG
                Section {
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
                #endif

                
                Divider()
                
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
    
    enum AppStorageResetter {
        static let onboardingKey = "hasCompletedOnboarding"
        
        static let tutorialKeys = [
            "hasSeenFloatingButtonTutorial",
            "hasSeenSlideToReplyTutorial"
        ]
        
        static func resetTutorials() {
            for key in tutorialKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.synchronize()
        }
        
        static func resetOnboarding() {
            UserDefaults.standard.removeObject(forKey: onboardingKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    // MARK: - Subviews
    private var callsignView: some View {
        VStack {
            Text("Callsign:")
            TextField("", text: $callsignText)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 120)
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
    }
    
    private var locatorView: some View {
        VStack {
            Text("Locator:")
            TextField("", text: $viewModel.locator)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .textCase(.uppercase)
                .frame(width: 80)
                .focused($focusedInput, equals: .locator)
                .lineLimit(1)
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
    }
    
    private var modeView: some View {
        VStack {
            Text("Mode:")
            Picker("", selection: Binding(
                get: { viewModel.isFT4 },
                set: { newValue in
                    Task { @MainActor in
                        viewModel.switchModeWhileRX(isFT4: newValue)
                        AnalyticsManager.shared.trackRadioModeChange(isFT4: newValue)
                        let modeStr = newValue ? "FT4" : "FT8"
                        let cycleStr: String
                        if newValue { // FT4
                            cycleStr = viewModel.evenCycle ? "even (0s)" : "odd (7.5s)"
                        } else { // FT8
                            cycleStr = viewModel.evenCycle ? "even (0/30s)" : "odd (15/45s)"
                        }
                        appLogger.log(.info, "Mode changed to \(modeStr), current cycle: \(cycleStr)")
                    }
                }
            )) {
                Text("FT8").tag(false)
                Text("FT4").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }
    
    private var cycleView: some View {
        VStack {
            Text("Transmission cycle:")
            Picker("", selection: Binding(
                get: { viewModel.evenCycle },
                set: { newValue in
                    viewModel.evenCycle = newValue
                    if viewModel.isFT4 {
                        let offset = newValue ? 0.0 : 7.5
                        appLogger.log(.info, "FT4 cycle changed to \(newValue ? "even" : "odd") — offset: \(offset)s")
                    } else {
                        let offset = newValue ? 0.0 : 15.0
                        appLogger.log(.info, "FT8 cycle changed to \(newValue ? "even" : "odd") — offsets: \(offset)/\(offset + 30.0)s")
                    }
                }
            )) {
                if viewModel.isFT4 {
                    Text("0").tag(true)
                    Text("7.5").tag(false)
                } else {
                    Text("0/30").tag(true)
                    Text("15/45").tag(false)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
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
                        .onSubmit {
                            commitFrequencyText()
                        }
                        .frame(width: 80)
                    Text("kHz")
                        .padding(5)
                }
            }.padding(.horizontal, 40)
            
            HStack {
                Button {
                    viewModel.frequency = max(0, viewModel.frequency - 10)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderedProminent)
                
                Slider(value: $viewModel.frequency, in: 0.1 ... 3000, step: 10)
                
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
    
    private var bandView: some View {
        let bands = FT8Message.Band.validBands
        let mode: FT8Message.FT8MessageMode = viewModel.isFT4 ? .ft4 : .ft8
        let frequencyHz = viewModel.selectedBand.frequency(for: mode)

        let frequencyText: String = {
            guard let hz = frequencyHz else {
                return "— " + String(localized: "MHz")
            }
            return String(format: "%.3f ", hz / 1_000_000) + String(localized: "MHz")
        }()

        let selectedIndex: Int? = bands.firstIndex(of: viewModel.selectedBand)

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Band:")
                Text(frequencyText)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                HStack(spacing: 6) {

                    // MARK: - Left arrow
                    Button {
                        guard let index = selectedIndex, index > 0 else { return }
                        let newBand = bands[index - 1]
                        withAnimation {
                            viewModel.selectedBand = newBand
                            proxy.scrollTo(newBand, anchor: .center)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIndex == 0)

                    // MARK: - Scrollable bands
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(bands, id: \.self) { band in
                                Button {
                                    withAnimation {
                                        viewModel.selectedBand = band
                                        proxy.scrollTo(band, anchor: .center)
                                    }
                                } label: {
                                    Text(band.rawValue)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            band == viewModel.selectedBand
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.2)
                                        )
                                        .foregroundColor(
                                            band == viewModel.selectedBand
                                            ? .white
                                            : .primary
                                        )
                                        .clipShape(Capsule())
                                }
                                .id(band)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    // MARK: - Right arrow
                    Button {
                        guard let index = selectedIndex, index < bands.count - 1 else { return }
                        let newBand = bands[index + 1]
                        withAnimation {
                            viewModel.selectedBand = newBand
                            proxy.scrollTo(newBand, anchor: .center)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIndex == bands.count - 1)
                }
                .padding(.horizontal, 20)
            }
        }
    }



    
    private var viewModeView: some View {
        VStack {
            Text("View mode: ")
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
            .padding(.horizontal, 10)
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
                TextField("Retries", value: $viewModel.maxRetrySlots, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .focused($focusedInput, equals: .retries)
                    .lineLimit(1)
                    .frame(width: 50)
                Text("Retries")
                    .font(.body)
                    .accessibilityLabel(Text("Retransmission retries"))
                    .accessibilityHint(Text("Number of times to resend messages if not acknowledged"))
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
            Text("Privacy & Anonymous Statistics")
            
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
            .padding(.horizontal, 8)
        }
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
        .multilineTextAlignment(.center)
    }
}

#Preview("ConfigurationView") {
    ConfigurationView()
        .environmentObject(
            FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            )
        )
        .environmentObject(FeatureFlagManager.shared)
}
