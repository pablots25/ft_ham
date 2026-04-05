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
    @EnvironmentObject private var premiumManager: PremiumManager
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
                            .padding(.horizontal)
                    } label: {
                        Label("Station", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    
                    NavigationLink {
                        RadioSettingsView()
                        .padding(.horizontal)
                    } label: {
                        Label("Radio", systemImage: "dial.low")
                    }
                    
                    NavigationLink {
                        BehaviorSettingsView()
                        .padding(.horizontal)
                    } label: {
                        Label("Behavior", systemImage: "gearshape.2")
                    }
                    
                    NavigationLink {
                        InterfaceSettingsView()
                        .padding(.horizontal)
                    } label: {
                        Label("Interface", systemImage: "rectangle.3.group")
                    }
                    
                    #if canImport(FTHamPremium)
                    if premiumManager.isPremiumUnlocked {
                        NavigationLink {
                            CatSettingsView(initialFrequencyMHz: viewModel.catDialFrequencyMHz)
                                .padding(.horizontal)
                        } label: {
                            Label("CAT Control", systemImage: "dot.radiowaves.left.and.right")
                        }
                    } else {
                        PremiumLockedRow(feature: .catControl) {
                            showPremium = true
                        }
                    }
                    #endif
                } header: {
                    Text("General")
                }
                // MARK: - Log Syncing (Premium)
                #if canImport(FTHamPremium)
                Section {
                    if premiumManager.isPremiumUnlocked {
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
                                    .padding([.horizontal])
                                    .padding([.bottom], 20)
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
                        PremiumLockedRow(feature: .qrzLogbook) {
                            showPremium = true
                        }

                        PremiumLockedRow(feature: .lotwSync) {
                            showPremium = true
                        }

                        PremiumLockedRow(feature: .eqslSync) {
                            showPremium = true
                        }
                    }
                } header: {
                    Text("Log Syncing")
                }
                #endif
                
                // MARK: - Debug
                #if DEBUG
                Section {
                    NavigationLink {
                        DebugSettingsView()
                        .padding(.horizontal)
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
                        ExternalActionRow(title: "Getting Started", systemImage: "book")
                    }
                    
                    Button {
                        showPremium = true
                    } label: {
                        ExternalActionRow(title: "Become Premium", systemImage: "star")
                    }
                    .accessibilityLabel("Become Premium")
                    
                    Button {
                        if let url = URL(string: "mailto:ftham@turrion.dev?subject=FT8%20Ham%20App%20Feedback") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        ExternalActionRow(title: "Send Feedback", systemImage: "envelope")
                    }
                } header: {
                    Text("Support")
                }
                
                // MARK: - About
                Section {
                    NavigationLink {
                        LegalAndPrivacyView()
                        .padding(.horizontal)
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
                PremiumPaywallView(source: "configuration")
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

private struct ExternalActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview("ConfigurationView") {
    NavigationStack {
        ConfigurationView(shouldScrollToDonations: .constant(false))
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
