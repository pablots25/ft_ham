//
//  ConfigurationView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - Settings Search Support

private struct SettingsSearchItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let section: String
    let keywords: [String]
    let destination: SettingsDestination

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return title.lowercased().contains(q)
            || keywords.contains { $0.lowercased().contains(q) }
    }
}

private enum SettingsDestination {
    case station, radio, behavior, interface
    #if canImport(FTHamPremium)
    case catControl, qrzLogbook, loTW, eQSL
    #endif
    #if DEBUG
    case debug
    #endif
    case legal
}

// MARK: - Configuration View

struct ConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @EnvironmentObject private var premiumManager: PremiumManager
    @Binding var shouldScrollToDonations: Bool

    @State private var showHelp = false
    @State private var showSupport = false
    @State private var showPremium = false
    @State private var searchText = ""

    var body: some View {
        List {
            if searchText.isEmpty {
                sectionedList
            } else {
                searchResultsList
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search settings…")
        .sheet(isPresented: $showSupport) {
            NavigationStack {
                SupportView()
                    .navigationTitle("Support FT HAM")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            CloseButton()
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
                            CloseButton()
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

    // MARK: - Sectioned List (default state)

    @ViewBuilder
    private var sectionedList: some View {
        Group {
            // MARK: General
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

            // MARK: Log Syncing (Premium)
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

            // MARK: Debug
            #if DEBUG
            Section {
                NavigationLink {
                    DebugSettingsView()
                        .padding(.horizontal)
                } label: {
                    Label("Debug", systemImage: "ladybug")
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

            // MARK: Help & Support
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

            // MARK: About
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

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsList: some View {
        if filteredItems.isEmpty {
            Section {
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        } else {
            Section("Results") {
                ForEach(filteredItems) { item in
                    NavigationLink {
                        destination(for: item.destination)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.section)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.systemImage)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Search Data

    private var allSettingsItems: [SettingsSearchItem] {
        var items: [SettingsSearchItem] = [
            .init(title: "Station",
                  systemImage: "antenna.radiowaves.left.and.right",
                  section: "General",
                  keywords: ["callsign", "grid", "locator", "gps"],
                  destination: .station),
            .init(title: "Radio",
                  systemImage: "dial.low",
                  section: "General",
                  keywords: ["band", "frequency", "mode", "ft8", "ft4"],
                  destination: .radio),
            .init(title: "Behavior",
                  systemImage: "gearshape.2",
                  section: "General",
                  keywords: ["auto tx", "cq", "timing", "schedule", "transmit"],
                  destination: .behavior),
            .init(title: "Interface",
                  systemImage: "rectangle.3.group",
                  section: "General",
                  keywords: ["theme", "view", "tutorial", "display", "appearance"],
                  destination: .interface),
        ]
        #if canImport(FTHamPremium)
        if premiumManager.isPremiumUnlocked {
            items += [
                .init(title: "CAT Control",
                      systemImage: "dot.radiowaves.left.and.right",
                      section: "General",
                      keywords: ["rig", "transceiver", "serial", "hamlib", "cat"],
                      destination: .catControl),
                .init(title: "QRZ Logbook",
                      systemImage: "network",
                      section: "Log Syncing",
                      keywords: ["qrz", "logbook", "xml", "upload", "log"],
                      destination: .qrzLogbook),
                .init(title: "LoTW",
                      systemImage: "checkmark.seal",
                      section: "Log Syncing",
                      keywords: ["lotw", "arrl", "certificate", "award"],
                      destination: .loTW),
                .init(title: "eQSL",
                      systemImage: "envelope.badge.shield.half.filled",
                      section: "Log Syncing",
                      keywords: ["eqsl", "digital", "qsl", "card"],
                      destination: .eQSL),
            ]
        }
        #endif
        #if DEBUG
        items.append(.init(title: "Debug",
                           systemImage: "ladybug",
                           section: "Debug",
                           keywords: ["developer", "flags", "feature", "testing"],
                           destination: .debug))
        #endif
        items.append(.init(title: "Legal & Licenses",
                           systemImage: "hand.raised",
                           section: "About",
                           keywords: ["privacy", "license", "terms", "legal", "open source"],
                           destination: .legal))
        return items
    }

    private var filteredItems: [SettingsSearchItem] {
        guard !searchText.isEmpty else { return [] }
        return allSettingsItems.filter { $0.matches(searchText) }
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destination(for dest: SettingsDestination) -> some View {
        switch dest {
        case .station:
            StationSettingsView().padding(.horizontal)
        case .radio:
            RadioSettingsView().padding(.horizontal)
        case .behavior:
            BehaviorSettingsView().padding(.horizontal)
        case .interface:
            InterfaceSettingsView().padding(.horizontal)
        #if canImport(FTHamPremium)
        case .catControl:
            CatSettingsView(initialFrequencyMHz: viewModel.catDialFrequencyMHz)
                .padding(.horizontal)
        case .qrzLogbook:
            ScrollView {
                QRZSettingsView()
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .navigationTitle("QRZ Logbook")
            .navigationBarTitleDisplayMode(.inline)
        case .loTW:
            ScrollView {
                LoTWSettingsView()
                    .padding([.horizontal])
                    .padding([.bottom], 20)
            }
            .navigationTitle("LoTW")
            .navigationBarTitleDisplayMode(.inline)
        case .eQSL:
            ScrollView {
                eQSLSettingsView()
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .navigationTitle("eQSL")
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if DEBUG
        case .debug:
            DebugSettingsView().padding(.horizontal)
        #endif
        case .legal:
            LegalAndPrivacyView().padding(.horizontal)
        }
    }

    // MARK: - Version Footer

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
