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

// MARK: - Configuration View

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case vertical = "Vertical"
    case separated = "TX/RX Separated"
    case condensed = "Condensed"

    var id: String { rawValue }

    var textKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

struct ConfigurationView: View {
    @EnvironmentObject private var flags: FeatureFlagManager

    @EnvironmentObject private var viewModel: FT8ViewModel
    
    @State private var showHelp = false
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
    
    private let minGain: Float = 0.1
    private let maxGain: Float = 2.0
    
    // Editable local state
    @State private var callsignText: String = ""
    @State private var frequencyText: String = ""
    
    // CQ modifier state
    @AppStorage("cqModifier") private var cqModifier: String = "NONE"
    @AppStorage("myPotaRef") private var myPotaRef: String = ""
    @AppStorage("mySotaRef") private var mySotaRef: String = ""
    @AppStorage("myWwffRef") private var myWwffRef: String = ""
    @AppStorage("myIotaRef") private var myIotaRef: String = ""
    
    let configColumns = [GridItem(.flexible()), GridItem(.flexible())]
    
    // MARK: - Number formatter for frequency input
    
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
                
                VStack(spacing: 0){
                    LazyVGrid(columns: configColumns, spacing: 10) {
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
                
                cqModifierSection
                
                Divider()
                
                LazyVGrid(columns: configColumns, spacing: 10) {
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
                
                analyticsSection
                
                #if DEBUG
                NavigationLink(destination: LogsView()) {
                    Text("View app logs")
                        .foregroundStyle(.blue)
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
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        
        // Commit on focus change
        .onChange(of: focusedInput) { newValue in
            if lastFocusedInput == .callsign && newValue != .callsign {
                commitCallsign()
            }
            if lastFocusedInput == .locator && newValue != .locator {
                commitLocator()
            }
            if lastFocusedInput == .frequency && newValue != .frequency {
                commitFrequencyText()
                        lastFocusedInput = newValue
            }
        }
        .onTapGesture {
            focusedInput = nil
            hideKeyboard()
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
            validCallsign = isValidCallsign(newValue)
            if validCallsign && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
        .onChange(of: viewModel.locator) { newValue in
            validLocator = isValidLocator(newValue)
            if validLocator && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
        .onChange(of: viewModel.frequency) { newValue in
            if focusedInput != .frequency {
                frequencyText = Self.frequencyFormatter.string(
                    from: NSNumber(value: newValue / 1000)
                ) ?? frequencyText
            }
            if newValue > 0 {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
    }
    
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
                .onChange(of: callsignText) { newValue in
                    callsignText = newValue.uppercased()
                    validCallsign = isValidCallsign(callsignText)
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
                return "— MHz"
            }
            return String(format: "%.3f MHz", hz / 1_000_000)
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
        let togglesColumns = [
            GridItem(.flexible())
        ]
        
        return LazyVGrid(
            columns: togglesColumns,
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Toggle("", isOn: $viewModel.autoRXAtStart)
                    .labelsHidden()
                Text("Auto RX at start")
            }
            
            HStack {
                Toggle("", isOn: $viewModel.autoCQReplyEnabled)
                    .labelsHidden()
                Text("Reply to CQ received")
            }
            
            HStack {
                Toggle("", isOn: $viewModel.decodeSelfTXMessages)
                    .labelsHidden()
                Text("Show TX messages in RX list")
                    .multilineTextAlignment(.leading)
            }
            
            HStack {
                Toggle("", isOn: $viewModel.holdTXFrequency)
                    .labelsHidden()
                Text("Hold TX frequecy")
            }
        }
        .padding(.horizontal)
    }

    private var cqModifierSection: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack{
                Text("CQ Modifier")
                    .font(.headline)
                    .padding(.horizontal)
                
                
                Picker("CQ Type", selection: $cqModifier) {
                    Text("None").tag("NONE")
                    
                    // Geographic filters (never in ADIF)
                    Text("DX (Long distance)").tag("DX")
                    Text("EU (Europe)").tag("EU")
                    Text("NA (North America)").tag("NA")
                    Text("SA (South America)").tag("SA")
                    Text("AF (Africa)").tag("AF")
                    Text("AS (Asia)").tag("AS")
                    Text("OC (Oceania)").tag("OC")
                    Text("ANT (Antarctica)").tag("ANT")
                    
                    // Activation modifiers (go to ADIF)
                    Text("POTA (Parks)").tag("POTA")
                    Text("SOTA (Summits)").tag("SOTA")
                    Text("WWFF (Flora & Fauna)").tag("WWFF")
                    Text("IOTA (Islands)").tag("IOTA")
                }
                .pickerStyle(.automatic)
                .padding(.horizontal, 5)
                .padding(.vertical, 0)
            }
            
            if cqModifier == "POTA" {
                HStack {
                    Text("POTA Reference:")
                    TextField("e.g. EA-1234", text: $myPotaRef)
                        .textFieldStyle(.roundedBorder)
                        .textCase(.uppercase)
                        .autocapitalization(.allCharacters)
                }
                .padding(.horizontal)
            } else if cqModifier == "SOTA" {
                HStack {
                    Text("SOTA Reference:")
                    TextField("e.g. EA/MD-001", text: $mySotaRef)
                        .textFieldStyle(.roundedBorder)
                        .textCase(.uppercase)
                        .autocapitalization(.allCharacters)
                }
                .padding(.horizontal)
            } else if cqModifier == "WWFF" {
                HStack {
                    Text("WWFF Reference:")
                    TextField("e.g. EAFF-0456", text: $myWwffRef)
                        .textFieldStyle(.roundedBorder)
                        .textCase(.uppercase)
                        .autocapitalization(.allCharacters)
                }
                .padding(.horizontal)
            } else if cqModifier == "IOTA" {
                HStack {
                    Text("IOTA Reference:")
                    TextField("e.g. EU-005", text: $myIotaRef)
                        .textFieldStyle(.roundedBorder)
                        .textCase(.uppercase)
                        .autocapitalization(.allCharacters)
                }
                .padding(.horizontal)
            }
        }
        
    }
    
    private var qsoConfigSection: some View {
        let togglesColumns = [
            GridItem(.flexible())
        ]
        
        return LazyVGrid(
            columns: togglesColumns,
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Toggle("", isOn: $viewModel.autoSequencingEnabled)
                    .labelsHidden()
                Text("Auto-sequence")
            }
            
            HStack{
                HStack(spacing: 0) {
                    TextField("Retries", value: $viewModel.maxRetrySlots, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .focused($focusedInput, equals: .retries)
                        .lineLimit(1)
                        .frame(width: 60)
                }
                Text("Retransmission retries")
            }
            
            HStack {
                Toggle("", isOn: $viewModel.autoQSOLogging)
                    .labelsHidden()
                Text("Auto QSO logging")
            }
        }
        .padding(.horizontal)
    }
    
    private var analyticsSection: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Privacy & Anonymous Statistics")
            
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { AnalyticsManager.shared.isAnalyticsEnabled },
                        set: { AnalyticsManager.shared.isAnalyticsEnabled = $0 }
                    ))
                    .labelsHidden()
                    
                    VStack(alignment: .center, spacing: 2) {
                        Text("Share usage statistics")
                        Text("Helps improve the app using anonymous, non-tracking statistics.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal)
        }
    }
    
    private var versionSection: some View {
        VStack(spacing: 4) {
            Text("Version")
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (Build \(build))")
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
}
