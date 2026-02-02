//
//  ContentView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 18/10/25.
//

import SwiftUI
import FirebaseAnalytics
import Combine

// MARK: - Main view

struct ContentView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms: Bool = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("autoRXAtStart") private var autoRXAtStart: Bool = false
    @State private var shareURL: URL?
    
    @State private var selectedTab = 0 // Default to TX/RX tab
    @State private var showConfigAlert = false
    @State private var showClearLogbookAlert = false
    @State private var shouldNavigateToConfiguration = false
    @State private var isPresentingOnboarding = false
    @State private var isPresentingLicense = false

    var body: some View {
        mainLayout
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
            .task {
                viewModel.startProgressBarUTC()
                // Decide which prompt to show at launch
                if !hasCompletedOnboarding {
                    isPresentingOnboarding = true
                } else if !hasAcceptedTerms {
                    isPresentingLicense = true
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
                    } else {
                        scheduleSettingsCheckIfNeeded()
                    }
                } else {
                    // If onboarding was reset (e.g. from ConfigurationView), show it immediately
                    isPresentingOnboarding = true
                }
            }
            .onChange(of: hasAcceptedTerms) { accepted in
                if accepted {
                    // After license is accepted, check settings
                    scheduleSettingsCheckIfNeeded()
                }
            }
            .onChange(of: autoRXAtStart) { enabled in
                if enabled {
                    evaluateAutoRX()
                } else {
                    // Stop RX immediately if user disables toggle
                    viewModel.stopSequencer()
                }
            }
            .onChange(of: viewModel.settingsLoaded) { loaded in
                if loaded && selectedTab == 4 {
                    selectedTab = 0
                }
                if loaded && autoRXAtStart {
                    evaluateAutoRX()
                }
            }
            .onAppear {
                AnalyticsManager.shared.trackScreen(.home)
            }
    }

    // MARK: - Main Layout
    
    private var mainLayout: some View {
        GeometryReader { geo in
            // Detect landscape normally, force portrait on iPad
            let isLandscape = (UIDevice.current.userInterfaceIdiom == .pad) ? false : (geo.size.width > geo.size.height)

            VStack(spacing: 0) {
                // MARK: - Header

                if isLandscape {
                    headerLandscape
                } else {
                    headerPortrait(geo: geo)
                }

                // MARK: - TabView

                TabView(selection: $selectedTab) {

                    TransmissionRootView()
                        .tabItem {
                            Label("TX/RX", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .tag(0)
                        .onAppear {
                                    AnalyticsManager.shared.trackScreen(.txRx)
                                }

                    FullScreenWaterfallView()
                        .tabItem { Label("Waterfall", systemImage: "waveform") }
                        .tag(1)
                        .onAppear {
                            AnalyticsManager.shared.trackScreen(.waterfall)
                        }


                    GridMapViewWrapper(
                        locators: $viewModel.workedLocators,
                        countries: $viewModel.workedCountryPairs
                    )
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(2)
                    .onAppear {
                        AnalyticsManager.shared.trackScreen(.map)
                    }

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
                                    ShareLink(
                                        item: viewModel.adifURL!,
                                        preview: SharePreview(
                                            "FTHam Logbook ADIF",
                                            icon: Image(systemName: "book")
                                        )
                                    ) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .disabled(viewModel.qsoList.isEmpty)
                                }
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
                        ConfigurationView()
                            .navigationTitle("Configuration")
                            .navigationBarTitleDisplayMode(.inline)
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
                if hasCompletedOnboarding && hasAcceptedTerms && viewModel.settingsLoaded {
                    InAppPrompts.shared.checkPrompts()
                }
            }
        }
    }
    
    // MARK: - Prompt sequencing helpers
    private func scheduleSettingsCheckIfNeeded() {
        // Avoid showing settings alert while a full-screen cover is presented
        guard !isPresentingOnboarding && !isPresentingLicense else { return }
        if !viewModel.settingsLoaded {
            showConfigAlert = true
            shouldNavigateToConfiguration = true
        }
    }
    
    // MARK: - Auto RX orchestration
    private func evaluateAutoRX() {
        // Gates: onboarding complete, terms accepted, settings valid, and autoRX enabled
        guard hasCompletedOnboarding,
              hasAcceptedTerms,
              viewModel.settingsLoaded,
              autoRXAtStart else {
            return
        }
        // Do not start during full-screen overlays
        guard !isPresentingOnboarding && !isPresentingLicense else { return }
        // Prevent double start
        guard !viewModel.isSequencerRunning else { return }
        // Start RX
        viewModel.startSequencer()
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
                Text("Received")
                    .tag(Pane.received)

                Text("Transmitted")
                    .tag(Pane.transmitted)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 25)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Progress bar subview

    private var progressBar: some View {
        let cycleLength = viewModel.isFT4 ? 7.5 : 15.0
        let seconds = min(Int(viewModel.cycleProgress * cycleLength), Int(cycleLength))

        return HStack {
            Text("\(seconds)/\(Int(cycleLength))")
                .font(.caption)
                .foregroundStyle(.gray)
            ProgressView(value: viewModel.cycleProgress)
                .progressViewStyle(.linear)
                .tint(.green)
        }
        .animation(.linear(duration: 0.2), value: viewModel.cycleProgress)
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
        HStack(spacing: 20) {
            Text("FT Ham")
                .font(.title)
                .frame(alignment: .leading)
            Spacer()
            ClockView()
            Spacer()
            StatusView()
            Spacer()
            progressBar
                .frame(maxWidth: 400, alignment: .trailing)
        }
        .padding(.top, 15)
        .padding(.bottom, 10)
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
        .environment(\.locale, .init(identifier: "es"))
}

