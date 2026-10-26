//
//  LegacyConfigurationView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import SwiftUI

struct LegacyConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var premiumManager: PremiumManager
    @EnvironmentObject private var flags: FeatureFlagManager
    @Binding var shouldScrollToDonations: Bool

    @State private var showHelp = false
    @State private var showSupport = false
    @State private var showPremium = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Station") {
                    StationSettingsContent()
                }

                section("Radio") {
                    RadioSettingsContent()
                }

                section("Audio") {
                    AudioSettingsContent()
                }

                section("Behavior") {
                    AutomationSettingsContent()
                }

                section("Display") {
                    DisplaySettingsContent()
                }

                section("Waterfall") {
                    WaterfallSettingsContent()
                }

                section("Reporting") {
                    ReportingSettingsContent()
                        .premiumLocked(!premiumManager.isPremiumUnlocked, feature: .pskReporter) {
                            showPremium = true
                        }
                }

                #if canImport(FTHamPremium)
                section("CAT Control") {
                    if premiumManager.isPremiumUnlocked {
                        NavigationLink {
                            CatSettingsView(initialFrequencyMHz: viewModel.catDialFrequencyMHz)
                                .padding(.horizontal)
                        } label: {
                            Label("Open CAT settings", systemImage: "dot.radiowaves.left.and.right")
                        }

                        if flags.isEnabled(.enableBandHopping) {
                            NavigationLink {
                                BandHopSettingsView(allowedBands: ConfigurationView.bandHopBands)
                            } label: {
                                Label("Band Hopping", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    } else {
                        Button {
                            showPremium = true
                        } label: {
                            HStack {
                                Label("Open CAT settings", systemImage: "dot.radiowaves.left.and.right")
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.secondary)

                        if flags.isEnabled(.enableBandHopping) {
                            Button {
                                showPremium = true
                            } label: {
                                HStack {
                                    Label("Band Hopping", systemImage: "arrow.triangle.2.circlepath")
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                #endif

                #if canImport(FTHamPremium)
                section("Log Syncing") {
                    if premiumManager.isPremiumUnlocked {
                        if flags.isEnabled(.enableICloudSync) {
                            NavigationLink {
                                ICloudSyncSettingsView()
                            } label: {
                                Label("iCloud Sync", systemImage: "icloud")
                            }
                        }

                        NavigationLink {
                            ScrollView {
                                QRZSettingsView()
                                    .padding(.horizontal)
                                    .padding(.bottom, 20)
                            }
                            .navigationTitle("QRZ Logbook")
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("QRZ Logbook", systemImage: "network")
                        }

                        NavigationLink {
                            ScrollView {
                                LoTWSettingsView()
                                    .padding(.horizontal)
                                    .padding(.bottom, 20)
                            }
                            .navigationTitle("LoTW")
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("LoTW", systemImage: "checkmark.seal")
                        }

                        NavigationLink {
                            ScrollView {
                                eQSLSettingsView()
                                    .padding(.horizontal)
                                    .padding(.bottom, 20)
                            }
                            .navigationTitle("eQSL")
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("eQSL", systemImage: "envelope.badge.shield.half.filled")
                        }
                    } else {
                        if flags.isEnabled(.enableICloudSync) {
                            Button {
                                showPremium = true
                            } label: {
                                HStack {
                                    Label("iCloud Sync", systemImage: "icloud")
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }

                        Button {
                            showPremium = true
                        } label: {
                            HStack {
                                Label("QRZ Logbook", systemImage: "network")
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.secondary)

                        Button {
                            showPremium = true
                        } label: {
                            HStack {
                                Label("LoTW", systemImage: "checkmark.seal")
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.secondary)

                        Button {
                            showPremium = true
                        } label: {
                            HStack {
                                Label("eQSL", systemImage: "envelope.badge.shield.half.filled")
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                #endif

                #if DEBUG
                section("Debug") {
                    NavigationLink {
                        DebugSettingsView()
                            .padding(.horizontal)
                    } label: {
                        Label("Debug", systemImage: "ladybug")
                    }

                    Button {
                        showSupport = true
                    } label: {
                        Label("Support FT HAM", systemImage: "heart")
                    }
                }
                #endif

                section("Premium") {
                    Button {
                        showPremium = true
                    } label: {
                        Label("Become Premium", systemImage: "star")
                    }
                    .accessibilityIdentifier("button_become_premium")
                }

                section("Help") {
                    Button {
                        showHelp = true
                    } label: {
                        Label("Getting Started", systemImage: "book")
                    }

                    NavigationLink {
                        TutorialsSettingsView()
                            .padding(.horizontal)
                    } label: {
                        Label("Tutorials", systemImage: "graduationcap")
                    }

                    if flags.isEnabled(.donationsEnabled) {
                        Button {
                            showSupport = true
                        } label: {
                            Label("Support FT HAM", systemImage: "heart")
                        }
                    }

                    Button {
                        if let url = URL(string: "mailto:ftham@turrion.dev?subject=FT8%20Ham%20App%20Feedback") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                }

                section("Legal") {
                    NavigationLink {
                        LegalAndPrivacyView()
                            .padding(.horizontal)
                    } label: {
                        Label("Legal & Licenses", systemImage: "hand.raised")
                    }
                }

                versionFooter
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
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
            // The paywall brings its own navigation bar and close button.
            PremiumPaywallView(source: .screen("configuration"))
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

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }
}

#Preview {
    NavigationStack {
        LegacyConfigurationView(shouldScrollToDonations: .constant(false))
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
            .environmentObject(FeatureFlagManager.shared)
    }
}
