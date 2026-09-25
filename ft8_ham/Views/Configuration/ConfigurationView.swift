//
//  ConfigurationView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - Settings Catalogue

/// Screens reachable from the configuration list. Rows that only trigger an
/// action (help links, the paywall) are not destinations; they are laid out
/// by hand in the Help section.
private enum SettingsDestination: Hashable {
    case station, radio, audio, automation, display, waterfall, reporting
    #if canImport(FTHamPremium)
    case catControl, bandHopping, qrzLogbook, loTW, eQSL, iCloudSync
    #endif
    case tutorials
    #if DEBUG
    case debug
    #endif
    case legal
}

private struct SettingsItem: Identifiable {
    let destination: SettingsDestination
    let title: String
    let systemImage: String
    /// Terms the search box should also match, beyond the title: the
    /// headings and notable controls inside the screen.
    let keywords: [String]
    /// Feature that must be unlocked to open the row; `nil` for free rows.
    let premiumFeature: PremiumFeature?
    /// Flag that must be on for the row to exist at all.
    let flag: FeatureFlag?

    // Stable identity: the catalogue is rebuilt on each body pass, and a fresh
    // UUID per pass would make SwiftUI recreate every row.
    var id: SettingsDestination { destination }

    init(
        _ destination: SettingsDestination,
        title: String,
        systemImage: String,
        keywords: [String] = [],
        premium: PremiumFeature? = nil,
        flag: FeatureFlag? = nil
    ) {
        self.destination = destination
        self.title = title
        self.systemImage = systemImage
        self.keywords = keywords
        self.premiumFeature = premium
        self.flag = flag
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return title.lowercased().contains(q)
            || keywords.contains { $0.lowercased().contains(q) }
    }
}

private struct SettingsGroup: Identifiable {
    let title: String
    let items: [SettingsItem]
    var id: String { title }
}

private struct SettingsSearchMatch: Identifiable {
    let item: SettingsItem
    let group: String
    var id: SettingsDestination { item.id }
}

// MARK: - Configuration View

struct ConfigurationView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var premiumManager: PremiumManager
    @EnvironmentObject private var flags: FeatureFlagManager
    @Binding var shouldScrollToDonations: Bool

    @State private var showHelp = false
    @State private var showSupport = false
    @State private var showPremium = false
    /// Feature whose locked row opened the paywall, for analytics attribution.
    @State private var paywallFeature: PremiumFeature?
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
                PremiumPaywallView(source: paywallFeature.map(PaywallSource.feature) ?? .screen("configuration"))
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
            Section {
                accountRow
            }

            // Sections are laid out one by one rather than through a
            // ForEach over `groups`: a List with a ForEach of Sections jumps
            // to the bottom when a flag flips and a row disappears.
            section(for: radioGroup)
            section(for: operatingGroup)
            #if canImport(FTHamPremium)
            section(for: logbookGroup)
            #endif

            // MARK: Help
            Section {
                Button {
                    showHelp = true
                } label: {
                    ExternalActionRow(title: "Getting Started", systemImage: "book")
                }

                row(for: tutorialsItem)

                Button {
                    if let url = URL(string: "mailto:ftham@turrion.dev?subject=FT8%20Ham%20App%20Feedback") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    ExternalActionRow(title: "Send Feedback", systemImage: "envelope")
                }

                if flags.isEnabled(.donationsEnabled) {
                    Button {
                        showSupport = true
                    } label: {
                        ExternalActionRow(title: "Support FT HAM", systemImage: "heart")
                    }
                }
            } header: {
                Text("Help")
            }

            // MARK: About
            Section {
                row(for: legalItem)
            } header: {
                Text("About")
            } footer: {
                versionFooter
            }

            #if DEBUG
            Section {
                row(for: debugItem)
            } header: {
                Text("Debug")
            }
            #endif
        }
        .padding(.horizontal)
    }

    /// Account-style row at the top, in the manner of the Apple Account row
    /// in Settings: who is operating, from where, and on which tier. Leads
    /// to the Station screen, where those details are edited.
    private var accountRow: some View {
        let callsign = viewModel.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        let locator = viewModel.locator.trimmingCharacters(in: .whitespacesAndNewlines)
        let tier = premiumManager.isPremiumUnlocked
            ? String(localized: "Premium")
            : String(localized: "Free")
        let details = [locator, tier].filter { !$0.isEmpty }.joined(separator: " · ")

        return NavigationLink {
            destination(for: .station)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.gradient)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    if callsign.isEmpty {
                        Text("Set up your station")
                            .font(.title3.weight(.semibold))
                        Text("Callsign and locator")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(callsign)
                            .font(.title3.weight(.semibold))
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowSeparator(.hidden, edges: .top)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("row_account")
    }

    // MARK: - Rows

    /// A locked row for gated features, a navigation link otherwise. The
    /// subtitle names the row's group in search results.
    @ViewBuilder
    private func row(for item: SettingsItem, subtitle: String? = nil) -> some View {
        if let feature = item.premiumFeature, !premiumManager.isPremiumUnlocked {
            PremiumLockedRow(feature: feature, title: item.title, systemImage: item.systemImage) {
                presentPaywall(for: feature)
            }
        } else {
            NavigationLink {
                destination(for: item.destination)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: item.systemImage)
                }
            }
        }
    }

    private func presentPaywall(for feature: PremiumFeature) {
        paywallFeature = feature
        showPremium = true
    }

    private func section(for group: SettingsGroup) -> some View {
        Section {
            ForEach(visibleItems(in: group)) { item in
                row(for: item)
            }
        } header: {
            Text(group.title)
        }
    }

    private func visibleItems(in group: SettingsGroup) -> [SettingsItem] {
        group.items.filter { item in
            item.flag.map { flags.isEnabled($0) } ?? true
        }
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
                ForEach(filteredItems) { match in
                    row(for: match.item, subtitle: match.group)
                }
            }
            .padding(.horizontal)
        }
    }

    private var filteredItems: [SettingsSearchMatch] {
        guard !searchText.isEmpty else { return [] }
        let searchable = [SettingsGroup(title: String(localized: "Station"), items: [stationItem])] + groups + [
            SettingsGroup(title: String(localized: "Help"), items: [tutorialsItem]),
            SettingsGroup(title: String(localized: "About"), items: [legalItem]),
        ]
        return searchable.flatMap { group in
            visibleItems(in: group)
                .filter { $0.matches(searchText) }
                .map { SettingsSearchMatch(item: $0, group: group.title) }
        }
    }

    // MARK: - Catalogue

    /// The navigable groups, in display order. Locked premium rows stay in
    /// the catalogue so they show up in search and lead to the paywall.
    private var groups: [SettingsGroup] {
        var result = [radioGroup, operatingGroup]
        #if canImport(FTHamPremium)
        result.append(logbookGroup)
        #endif
        return result
    }

    private var radioGroup: SettingsGroup {
        var items: [SettingsItem] = [
            .init(.radio,
                  title: String(localized: "Mode & Band"),
                  systemImage: "dial.low",
                  keywords: ["radio", "band", "dial", "frequency", "mode", "ft8", "ft4",
                             "cycle", "even", "odd", "clock", "time", "sync", "sntp"]),
            .init(.audio,
                  title: String(localized: "Audio"),
                  systemImage: "waveform",
                  keywords: ["audio", "offset", "tone", "gain", "rx gain", "input",
                             "microphone", "tx output", "level", "vox", "volume", "db"]),
        ]
        #if canImport(FTHamPremium)
        items += [
            .init(.catControl,
                  title: String(localized: "CAT Control"),
                  systemImage: "dot.radiowaves.left.and.right",
                  keywords: ["rig", "transceiver", "serial", "hamlib", "cat", "udp"],
                  premium: .catControl),
            .init(.bandHopping,
                  title: String(localized: "Band Hopping"),
                  systemImage: "arrow.triangle.2.circlepath",
                  keywords: ["band", "hop", "rotate", "schedule", "cat"],
                  premium: .bandHopping,
                  flag: .enableBandHopping),
        ]
        #endif
        return SettingsGroup(title: String(localized: "Radio"), items: items)
    }

    private var operatingGroup: SettingsGroup {
        SettingsGroup(title: String(localized: "Operating"), items: [
            .init(.automation,
                  title: String(localized: "Automation"),
                  systemImage: "gearshape.2",
                  keywords: ["auto rx", "cq", "reply", "auto-sequence", "sequence",
                             "retries", "pile-up", "pileup", "logging", "hold tx",
                             "transmit", "behavior"]),
            .init(.display,
                  title: String(localized: "Display"),
                  systemImage: "rectangle.3.group",
                  keywords: ["view mode", "list", "highlight", "badges", "new grid",
                             "dxcc", "gesture", "double tap", "appearance", "interface"]),
            .init(.waterfall,
                  title: String(localized: "Waterfall"),
                  systemImage: "waveform",
                  keywords: ["waterfall", "spectrum", "palette", "color", "colour",
                             "gain", "zero", "level", "flatten", "noise"]),
            .init(.reporting,
                  title: String(localized: "Reporting"),
                  systemImage: "dot.radiowaves.up.forward",
                  keywords: ["psk", "pskreporter", "spots", "map", "online",
                             "presence", "community"],
                  premium: .pskReporter),
        ])
    }

    #if canImport(FTHamPremium)
    private var logbookGroup: SettingsGroup {
        SettingsGroup(title: String(localized: "Logbook"), items: [
            .init(.iCloudSync,
                  title: String(localized: "iCloud Sync"),
                  systemImage: "icloud",
                  keywords: ["icloud", "sync", "backup", "devices", "cloudkit"],
                  premium: .iCloudSync,
                  flag: .enableICloudSync),
            .init(.qrzLogbook,
                  title: String(localized: "QRZ Logbook"),
                  systemImage: "network",
                  keywords: ["qrz", "logbook", "xml", "upload", "log"],
                  premium: .qrzLogbook),
            .init(.loTW,
                  title: String(localized: "LoTW"),
                  systemImage: "checkmark.seal",
                  keywords: ["lotw", "arrl", "certificate", "award"],
                  premium: .lotwSync),
            .init(.eQSL,
                  title: String(localized: "eQSL"),
                  systemImage: "envelope.badge.shield.half.filled",
                  keywords: ["eqsl", "digital", "qsl", "card"],
                  premium: .eqslSync),
        ])
    }
    #endif

    /// Reached through the account row rather than a list row, but still
    /// offered by search.
    private var stationItem: SettingsItem {
        .init(.station,
              title: String(localized: "Station"),
              systemImage: "antenna.radiowaves.left.and.right",
              keywords: ["callsign", "grid", "locator", "gps", "11 m", "cb",
                         "cq", "modifier", "pota", "sota"])
    }

    private var tutorialsItem: SettingsItem {
        .init(.tutorials,
              title: String(localized: "Tutorials"),
              systemImage: "graduationcap",
              keywords: ["onboarding", "help", "tips", "tutorial", "reset"])
    }

    private var legalItem: SettingsItem {
        .init(.legal,
              title: String(localized: "Legal & Licenses"),
              systemImage: "hand.raised",
              keywords: ["privacy", "license", "terms", "legal", "open source"])
    }

    #if DEBUG
    private var debugItem: SettingsItem {
        .init(.debug,
              title: String(localized: "Debug"),
              systemImage: "ladybug",
              keywords: ["developer", "flags", "feature", "testing"])
    }
    #endif

    /// Bands with an FT8 dial frequency, as offered by the band-hop editor.
    static var bandHopBands: [String] {
        FT8Message.Band.allCases
            .filter { $0.frequency(for: .ft8) != nil && $0 != .custom && $0 != .unknown }
            .map(\.rawValue)
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destination(for dest: SettingsDestination) -> some View {
        switch dest {
        case .station:
            StationSettingsView().padding(.horizontal)
        case .radio:
            RadioSettingsView().padding(.horizontal)
        case .audio:
            AudioSettingsView().padding(.horizontal)
        case .automation:
            AutomationSettingsView().padding(.horizontal)
        case .display:
            DisplaySettingsView().padding(.horizontal)
        case .waterfall:
            WaterfallSettingsView().padding(.horizontal)
        case .reporting:
            ReportingSettingsView().padding(.horizontal)
        #if canImport(FTHamPremium)
        case .catControl:
            CatSettingsView(initialFrequencyMHz: viewModel.catDialFrequencyMHz)
                .padding(.horizontal)
        case .bandHopping:
            BandHopSettingsView(allowedBands: Self.bandHopBands)
        case .iCloudSync:
            ICloudSyncSettingsView()
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
                    .padding(.horizontal)
                    .padding(.bottom, 20)
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
        case .tutorials:
            TutorialsSettingsView().padding(.horizontal)
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
