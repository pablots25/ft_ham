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
    /// Deliberately NOT observed: this view hosts all five tabs, so observing
    /// the whole view model would re-evaluate the entire app on every publish
    /// (each decoded message, each settings write, each CAT poll...). The few
    /// values it needs are read from `viewModel.rootState` instead.
    let viewModel: FT8ViewModel
    @ObservedObject private var root: RootUIState
    @EnvironmentObject private var flags: FeatureFlagManager
    @StateObject private var progressVM = ProgressViewModel()
    @ObservedObject private var prompts = InAppPrompts.shared
    private let mapSettings = MapSettingsModel.shared

    init(viewModel: FT8ViewModel) {
        self.viewModel = viewModel
        self._root = ObservedObject(wrappedValue: viewModel.rootState)
    }
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms: Bool = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedInitialPermissionFlow") private var hasCompletedInitialPermissionFlow: Bool = false
    @AppStorage("autoRXAtStart") private var autoRXAtStart: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @AppStorage("lastSelectedTab") private var lastSelectedTab: Int = 0

    @State private var selectedTab: Int = 0
    @State private var showConfigAlert = false
    @State private var shouldNavigateToConfiguration = false
    @State private var shouldScrollToDonations = false
    @State private var isPresentingOnboarding = false
    @State private var isPresentingLicense = false
    @State private var isPresentingWhatsNew = false
    @State private var isPresentingDonationPrompt = false
    @State private var isPresentingRevocationAlert = false
    /// Bumped when the app becomes active so the slot bar resyncs at once.
    @State private var progressResyncToken = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        mainLayout
            .toast($root.toast)
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
            // 4) Donation → Premium upgrade prompt (shown once)
            .sheet(isPresented: $isPresentingDonationPrompt) {
                DonationPremiumPromptView()
                    .environmentObject(PremiumManager.shared)
                    .interactiveDismissDisabled(true)
            }
            // 5) Premium revocation alert
            .alert("Premium Access Removed", isPresented: $isPresentingRevocationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your premium access has been removed. If this is unexpected, please contact Apple Support.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .premiumRevoked)) { _ in
                isPresentingRevocationAlert = true
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
                // Skip all full-screen covers in UI tests — the onboarding / terms
                // covers would block every interaction target on a fresh simulator.
                if !AppEnvironment.current.isUITest {
                    if !hasCompletedOnboarding {
                        isPresentingOnboarding = true
                    } else if !hasAcceptedTerms {
                        isPresentingLicense = true
                    } else if AppVersionManager.shared.shouldShowWhatsNew {
                        isPresentingWhatsNew = true
                    } else if PremiumManager.shared.isDonor && !PremiumManager.shared.didShowDonationPremiumPrompt {
                        isPresentingDonationPrompt = true
                    } else if !root.settingsLoaded {
                        showConfigAlert = true
                        shouldNavigateToConfiguration = true
                    }
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
                    if PremiumManager.shared.isDonor && !PremiumManager.shared.didShowDonationPremiumPrompt {
                        isPresentingDonationPrompt = true
                    } else {
                        scheduleSettingsCheckIfNeeded()
                        evaluateAutoRX()
                    }
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
            .onChange(of: root.settingsLoaded) { loaded in
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
            // Deferred a run loop turn: `@Published` emits before the value is
            // stored, so `consume()` would still read the old one.
            .onReceive(TabRouter.shared.$pendingTab.compactMap { $0 }.receive(on: RunLoop.main)) { _ in
                if let tab = TabRouter.shared.consume() { selectedTab = tab.rawValue }
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
                    MapTabView(isSelected: selectedTab == 2)
                    .onAppear {
                        AnalyticsManager.shared.trackScreen(.map)
                    }
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(2)
                    
                    NavigationStack {
                        LogbookView()
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
                if hasCompletedOnboarding && hasAcceptedTerms && hasCompletedInitialPermissionFlow && root.settingsLoaded {
                    InAppPrompts.shared.checkPrompts()
                }
            }
            .sheet(isPresented: $root.showFreeTextSheet) {
                FreeTextTXView()
                    .environmentObject(viewModel)
            }
        }
    }
    
    // MARK: - Prompt sequencing helpers
    private func scheduleSettingsCheckIfNeeded() {
        // Avoid showing settings alert while a full-screen cover is presented
        guard !isPresentingOnboarding,
              !isPresentingLicense,
              !isPresentingWhatsNew else { return }
        if !root.settingsLoaded {
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
              root.settingsLoaded,
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
    
    /// Map tab. Observes the view model here (not in `ContentView`) so only
    /// this subtree is re-evaluated when worked locators/countries change.
    struct MapTabView: View {
        @EnvironmentObject private var viewModel: FT8ViewModel
        /// The tab bar builds every tab's view up front, which would create
        /// the MapKit view (and start loading tiles) at launch. The map is
        /// only built once this tab has been shown, and kept from then on.
        let isSelected: Bool
        @State private var hasBeenSelected = false

        var body: some View {
            Group {
                if hasBeenSelected || isSelected {
                    map
                } else {
                    Color.clear
                }
            }
            .onChange(of: isSelected) { selected in
                if selected { hasBeenSelected = true }
            }
            .onAppear {
                if isSelected { hasBeenSelected = true }
            }
        }

        private var map: some View {
            GridMapViewWrapper(
                locators: viewModel.workedLocators,
                countries: viewModel.workedCountryPairs,
                mapSettings: MapSettingsModel.shared,
                heardMe: HeardMeStore.shared,
                myCallsign: viewModel.callsign,
                myLocator: viewModel.locator,
                isActive: isSelected,
                onUserLocator: { [weak viewModel] locator in
                    viewModel?.addUserLocator(locator)
                }
            )
            .equatable()
        }
    }

    struct TransmissionRootView: View {
        @EnvironmentObject private var viewModel: FT8ViewModel

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
        @EnvironmentObject private var mapSettings: MapSettingsModel
        @EnvironmentObject private var flags: FeatureFlagManager
        
        private var isDashboardEnabled: Bool {
            #if DEBUG
            return true
            #else
            return flags.isEnabled(.enableIpadDashboard)
            #endif
        }
        
        var body: some View {
            Group {
                if isDashboardEnabled {
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
        // The message-color legend is reachable from the column header inside
        // SeparatedTransmissionView, so no info button is repeated here.
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
        // Once a second: the seconds counter changes no faster, and the bar
        // animates itself between checks (see CycleProgressBar).
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let cycleLength = ProgressViewModel.cycleLengthForMode(isFT4: root.isFT4)
            let progress = progressVM.cycleProgress(isFT4: root.isFT4)
            let seconds = min(Int(progress * cycleLength), Int(cycleLength))

            HStack {
                Text("\(seconds)/\(Int(cycleLength))")
                    .font(.caption)
                    .foregroundStyle(.gray)
                CycleProgressBar(progress: progress, cycleLength: cycleLength, resyncToken: progressResyncToken)
                    .frame(height: CycleProgressBarView.height)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active { progressResyncToken &+= 1 }
        }
    }

    // MARK: - Header portrait

    private func headerPortrait(geo: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            Text("FT Ham")
                .font(.title)
                .lineLimit(1)
                .fixedSize()
            Spacer()
            progressBar
                .padding(.vertical)
        }
        .padding(.horizontal, 40)
        .operatingChromeTypeSize()
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
        .operatingChromeTypeSize()
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
        .operatingChromeTypeSize()
    }
}

// MARK: - Terms & Conditions View

struct TermsSheet: View {
    @Binding var hasAcceptedTerms: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showTermsSafari = false
    @State private var showPrivacySafari = false

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
                        Button("Terms of Use") { showTermsSafari = true }
                        Button("Privacy Policy") { showPrivacySafari = true }
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
            .sheet(isPresented: $showTermsSafari) {
                SafariView(url: URL(string: "https://ftham.turrion.dev/terms")!)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showPrivacySafari) {
                SafariView(url: URL(string: "https://ftham.turrion.dev/privacy")!)
                    .ignoresSafeArea()
            }
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
    
    return ContentView(viewModel: viewModel)
            .environmentObject(viewModel)
            .environmentObject(FeatureFlagManager.shared)
            .environmentObject(PremiumManager.shared)
            .environment(\.locale, .init(identifier: "en"))
}

#Preview("ContentView – ES") {
    let viewModel = FT8ViewModel(
        txMessages: PreviewMocks.txMessages,
        rxMessages: PreviewMocks.rxMessages
    )
    
    viewModel.callsign = "EA4IQL"
    viewModel.locator = "IN80"
    
    return ContentView(viewModel: viewModel)
        .environmentObject(viewModel)
        .environmentObject(FeatureFlagManager.shared)
        .environmentObject(PremiumManager.shared)
        .environment(\.locale, .init(identifier: "es"))
}

