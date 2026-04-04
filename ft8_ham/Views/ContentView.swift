//
//  ContentView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 18/10/25.
//

import SwiftUI
import Combine

// MARK: - Main view

struct ContentView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @StateObject private var progressVM = ProgressViewModel()
    @ObservedObject private var prompts = InAppPrompts.shared
    @ObservedObject private var mapSettings = MapSettingsModel.shared
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms: Bool = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedInitialPermissionFlow") private var hasCompletedInitialPermissionFlow: Bool = false
    @AppStorage("autoRXAtStart") private var autoRXAtStart: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @AppStorage("lastSelectedTab") private var lastSelectedTab: Int = 0

    @State private var selectedTab: Int = 0
    @State private var showConfigAlert = false
    @State private var showClearLogbookAlert = false
    @State private var showExportOptions = false
    @State private var shouldNavigateToConfiguration = false
    @State private var shouldScrollToDonations = false
    @State private var isPresentingOnboarding = false
    @State private var isPresentingLicense = false
    @State private var isPresentingWhatsNew = false

    var body: some View {
        mainLayout
            .toast($viewModel.toast)
            // 1) Onboarding first
            .fullScreenCover(isPresented: $isPresentingOnboarding) {
                OnboardingView()
                    .interactiveDismissDisabled(true)
                    .onAppear { AnalyticsManager.shared.trackScreen(.onboarding) }
            }
            // 2) License/Terms second
            .fullScreenCover(isPresented: $isPresentingLicense) {
                TermsSheet(hasAcceptedTerms: $hasAcceptedTerms)
                    .interactiveDismissDisabled(true)
                    .onAppear { AnalyticsManager.shared.trackScreen(.terms) }
            }
            // 3) What's New third
            .fullScreenCover(isPresented: $isPresentingWhatsNew) {
                WhatsNewView()
                    .onAppear { AnalyticsManager.shared.trackScreen(.whatsNew) }
            }
            .task {
                // Set initial tab: 4 if first launch, otherwise last used tab
                if !hasLaunchedBefore {
                    selectedTab = 4
                    hasLaunchedBefore = true
                } else {
                    selectedTab = lastSelectedTab
                }
                // Users who completed onboarding before the permission flow existed
                // are grandfathered in — their OS dialogs were triggered by the old code.
                if hasCompletedOnboarding && !hasCompletedInitialPermissionFlow {
                    hasCompletedInitialPermissionFlow = true
                }
                // Decide which prompt to show at launch
                if !hasCompletedOnboarding {
                    isPresentingOnboarding = true
                } else if !hasAcceptedTerms {
                    isPresentingLicense = true
                } else if AppVersionManager.shared.shouldShowWhatsNew {
                    isPresentingWhatsNew = true
                } else if !viewModel.settingsLoaded {
                    showConfigAlert = true
                    shouldNavigateToConfiguration = true
                }
                // Once UI is ready, evaluate RX start
                evaluateAutoRX()
            }
            .onChange(of: hasCompletedOnboarding) { completed in
                if completed {
                    isPresentingOnboarding = false
                    if !hasAcceptedTerms {
                        isPresentingLicense = true
                    } else if AppVersionManager.shared.shouldShowWhatsNew {
                        isPresentingWhatsNew = true
                    } else {
                        scheduleSettingsCheckIfNeeded()
                        evaluateAutoRX()
                    }
                } else {
                    // If onboarding was reset (e.g. from ConfigurationView), show it immediately
                    isPresentingOnboarding = true
                }
            }
            .onChange(of: hasAcceptedTerms) { accepted in
                if accepted {
                    if AppVersionManager.shared.shouldShowWhatsNew {
                        isPresentingWhatsNew = true
                    } else {
                        scheduleSettingsCheckIfNeeded()
                        evaluateAutoRX()
                    }
                }
            }
            .onChange(of: isPresentingWhatsNew) { isPresented in
                if !isPresented {
                    scheduleSettingsCheckIfNeeded()
                    evaluateAutoRX()
                }
            }
            .onChange(of: autoRXAtStart) { enabled in
                if enabled {
                    evaluateAutoRX()
                } else {
                    // Stop RX immediately if user disables toggle
                    Task { @MainActor in
                        await viewModel.stopSequencer()
                    }
                }
            }
            .onChange(of: selectedTab) { newTab in
                lastSelectedTab = newTab
            }
            .onChange(of: viewModel.settingsLoaded) { loaded in
                if loaded && autoRXAtStart {
                    evaluateAutoRX()
                }
            }
            .onChange(of: prompts.shouldNavigateToDonations) { shouldNavigate in
                if shouldNavigate {
                    selectedTab = 4 // Navigate to Configuration tab
                    prompts.shouldNavigateToDonations = false
                    // Both old and new config views observe shouldScrollToDonations:
                    // - Old view scrolls to the donations section
                    // - New view presents the Support sheet
                    shouldScrollToDonations = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToConfiguration)) { _ in
                selectedTab = 4
            }

            .onAppear {
                AnalyticsManager.shared.trackScreen(.home)
            }
    }

    // MARK: - Main Layout
    
    private var mainLayout: some View {
        GeometryReader { geo in
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            let isLandscape = geo.size.width > geo.size.height

            VStack(spacing: 0) {
                // MARK: - Header

                if isIPad {
                    headerIPad
                } else if isLandscape {
                    headerLandscape
                } else {
                    headerPortrait(geo: geo)
                }

                // MARK: - TabView
                // Note: Not all tabs need NavigationStack. Only tabs with navigation bars,
                // toolbar items, or deep navigation (Logbook, Configuration) are wrapped.
                // Tabs 0-2 use direct views without navigation chrome.
                
                TabView(selection: $selectedTab) {
                    
                    TransmissionRootView()
                        .tabItem {
                            Label("TX/RX", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .tag(0)
                        .onAppear {
                                    AnalyticsManager.shared.trackScreen(.txRx)
                                }
                        .environmentObject(mapSettings)

                    FullScreenWaterfallView()
                        .tabItem { Label("Waterfall", systemImage: "waveform") }
                        .tag(1)
                        .onAppear {
                            AnalyticsManager.shared.trackScreen(.waterfall)
                        }
                    GridMapViewWrapper(
                        locators: $viewModel.workedLocators,
                        countries: $viewModel.workedCountryPairs,
                        showGrids: $mapSettings.showGrids,
                        showCountryCircles: $mapSettings.showCountryCircles,
                        showGeodesics: $mapSettings.showGeodesics,
                        showAnnotations: $mapSettings.showAnnotations
                    )
                    .onAppear {
                        AnalyticsManager.shared.trackScreen(.map)
                    }
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(2)
                    
                    NavigationStack {
                        LogbookView()
                            .navigationTitle("Logbook")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button("Clear") {
                                        showClearLogbookAlert = true
                                    }
                                    .disabled(viewModel.qsoList.isEmpty)
                                }
                                
                                ToolbarItem(placement: .automatic) {
                                    Button {
                                        showExportOptions = true
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .disabled(viewModel.qsoList.isEmpty)
                                }
                            }
                            .sheet(isPresented: $showExportOptions) {
                                ExportOptionsView()
                                    .environmentObject(viewModel)
                            }
                            .alert("Clear logbook?", isPresented: $showClearLogbookAlert) {
                                Button("Cancel", role: .cancel) {}
                                Button("Clear", role: .destructive) {
                                    viewModel.clearLogbookConfirmed()
                                }
                            } message: {
                                Text("This will permanently delete all QSOs.")
                            }
                            .onAppear {
                                AnalyticsManager.shared.trackScreen(.logbook)
                            }
                    }
                    .tabItem { Label("Logbook", systemImage: "book") }
                    .tag(3)
                    NavigationStack {
                        if flags.isEnabled(.newConfigView) {
                            ConfigurationView(shouldScrollToDonations: $shouldScrollToDonations)
                                .navigationTitle("Configuration")
                                .navigationBarTitleDisplayMode(.inline)
                        } else {
                            LegacyConfigurationView(shouldScrollToDonations: $shouldScrollToDonations)
                                .navigationTitle("Configuration")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    .onAppear {
                        AnalyticsManager.shared.trackScreen(.configuration)
                    }
                    .tabItem { Label("Configuration", systemImage: "gearshape") }
                    .tag(4)
                }

            }
            .alert("Callsign and Locator not configured", isPresented: $showConfigAlert) {
                Button("OK") {
                    if shouldNavigateToConfiguration {
                        selectedTab = 4
                        shouldNavigateToConfiguration = false
                    }
                }
            } message: {
                Text("Please fill in your callsign and locator in the Configuration tab to start using the app")
            }
            .onAppear {
                if hasCompletedOnboarding && hasAcceptedTerms && hasCompletedInitialPermissionFlow && viewModel.settingsLoaded {
                    InAppPrompts.shared.checkPrompts()
                }
            }
        }
    }
    
    // MARK: - Prompt sequencing helpers
    private func scheduleSettingsCheckIfNeeded() {
        // Avoid showing settings alert while a full-screen cover is presented
        guard !isPresentingOnboarding,
              !isPresentingLicense,
              !isPresentingWhatsNew else { return }
        if !viewModel.settingsLoaded {
            showConfigAlert = true
            shouldNavigateToConfiguration = true
        }
    }
    
    // MARK: - Auto RX orchestration
    private func evaluateAutoRX() {
        // Gates: onboarding complete, terms accepted, permissions flow done, settings valid, and autoRX enabled
        guard hasCompletedOnboarding,
              hasAcceptedTerms,
              hasCompletedInitialPermissionFlow,
              viewModel.settingsLoaded,
              autoRXAtStart else {
            return
        }
        // Do not start during full-screen overlays
        guard !isPresentingOnboarding,
              !isPresentingLicense,
              !isPresentingWhatsNew else { return }
        // Prevent double start
        guard !viewModel.isSequencerRunning else { return }
        // Start RX
        viewModel.startSequencer()
    }
    
    struct TransmissionRootView: View {
        @EnvironmentObject private var viewModel: FT8ViewModel
        @EnvironmentObject private var mapSettings: MapSettingsModel

        var body: some View {
            transmissionContent
                .transition(.opacity)
                .animation(.easeInOut, value: viewModel.selectedViewMode)

        }
        
        
        // MARK: - Transmission Mode Router
        
        @ViewBuilder
        private var transmissionContent: some View {
            switch viewModel.selectedViewMode {
            case .vertical:
                TransmissionView()

            case .separated:
                SeparatedTransmissionRootView()

            case .condensed:
                CondensedTransmissionView()
                
            case .dashboard:
                DashboardRootView()
            }
        }
    }
    
    struct DashboardRootView: View {
        @EnvironmentObject private var viewModel: FT8ViewModel
        @EnvironmentObject private var mapSettings: MapSettingsModel
        @EnvironmentObject private var flags: FeatureFlagManager
        
        var body: some View {
            Group {
                if flags.isEnabled(.enableIpadDashboard) {
                    IpadDashboardView()
                        .onAppear {
                            AnalyticsManager.shared.trackScreen(.ipadDashboard)
                        }
                        .environmentObject(mapSettings)
                } else {
                    // Fallback to separated view if dashboard is disabled
                    SeparatedTransmissionRootView()
                }
            }
        }
    }
    
    
    struct SeparatedTransmissionRootView: View {
        @State private var selectedPane: Pane = .received
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        enum Pane {
            case received
            case transmitted
        }

        var body: some View {

            VStack {
                if horizontalSizeClass == .regular {
                    panePicker
                        .padding()
                }

                if selectedPane == .received {
                    SeparatedTransmissionView(section: .received, allowReply: true)
                } else {
                    SeparatedTransmissionView(section: .transmitted, allowReply: false)
                }

                if horizontalSizeClass != .regular {
                    panePicker
                }
            }
        }

        // MARK: - Pane Picker
        private var panePicker: some View {
            Picker("Pane", selection: $selectedPane) {
                Text(String(localized: "Received"))
                    .tag(Pane.received)

                Text(String(localized: "Transmitted"))
                    .tag(Pane.transmitted)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 25)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Progress bar subview

    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let cycleLength = ProgressViewModel.cycleLengthForMode(isFT4: viewModel.isFT4)
            let progress = progressVM.cycleProgress(isFT4: viewModel.isFT4)
            let seconds = min(Int(progress * cycleLength), Int(cycleLength))

            HStack {
                Text("\(seconds)/\(Int(cycleLength))")
                    .font(.caption)
                    .foregroundStyle(.gray)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.green)
            }
            .animation(.linear(duration: 0.1), value: progress)
        }
    }

    // MARK: - Header portrait

    private func headerPortrait(geo: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            Text("FT Ham")
                .multilineTextAlignment(.center)
                .font(.title)
            Spacer()
            progressBar
                .padding(.vertical)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Header landscape

    private var headerLandscape: some View {
        HStack(spacing: LayoutConstants.headerSpacing) {
            Text("FT Ham")
                .font(.title)
                .frame(alignment: .leading)
            ClockView()
            StatusView()
            progressBar
                .frame(maxWidth: LayoutConstants.progressBarMaxWidth, alignment: .trailing)
        }
        .padding(.top, 15)
        .padding(.bottom, 10)
    }
    
    // MARK: - Header iPad
    
    private var headerIPad: some View {
        HStack(spacing: LayoutConstants.largePadding) {
            Text("FT Ham")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .frame(alignment: .leading)
            
            StatusView()
                .frame(minWidth: 150)
            
            progressBar
                .frame(maxWidth: LayoutConstants.progressBarMaxWidth, alignment: .trailing)
            
            ClockView()
                .frame(minWidth: 100)
        }
        .padding(.horizontal, LayoutConstants.ipadPadding)
        .padding(.vertical, 15)
    }
}

// MARK: - Terms & Conditions View

struct TermsSheet: View {
    @Binding var hasAcceptedTerms: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "onb_title_welcome"))
                    .font(.largeTitle)
                    .bold()

                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("By using this app, you agree to the Terms of Use and End-User License Agreement (EULA).")
                        
                    Text("Please review the full documents:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Link("Terms of Use", destination: URL(string: "https://ftham.turrion.dev/terms")!)
                        Link("Privacy Policy", destination: URL(string: "https://ftham.turrion.dev/privacy")!)
                    }
                    .font(.body)
                        .foregroundStyle(.blue)

                        Divider()
                        
                    Text("Anonymous usage metrics may be collected via Firebase Analytics to improve the app. No personally identifiable information (PII) is collected.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    AnalyticsManager.shared.grantAnalyticsConsent()
                    AnalyticsManager.shared.logTermsAccepted()
                    hasAcceptedTerms = true
                    dismiss()
                }) {
                    Text("I Accept")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
            .navigationBarTitle("Terms & Privacy", displayMode: .inline)
        }
    }
}


#Preview("ContentView – EN") {
    let viewModel = FT8ViewModel(
        txMessages: PreviewMocks.txMessages,
        rxMessages: PreviewMocks.rxMessages
    )
    
    viewModel.callsign = "EA4IQL"
    viewModel.locator = "IN80"
    
    return ContentView()
            .environmentObject(viewModel)
            .environmentObject(FeatureFlagManager.shared)
            .environment(\.locale, .init(identifier: "en"))
}

#Preview("ContentView – ES") {
    let viewModel = FT8ViewModel(
        txMessages: PreviewMocks.txMessages,
        rxMessages: PreviewMocks.rxMessages
    )
    
    viewModel.callsign = "EA4IQL"
    viewModel.locator = "IN80"
    
    return ContentView()
        .environmentObject(viewModel)
        .environmentObject(FeatureFlagManager.shared)
        .environment(\.locale, .init(identifier: "es"))
}

