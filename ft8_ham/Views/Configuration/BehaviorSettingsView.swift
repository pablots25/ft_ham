//
//  BehaviorSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

struct BehaviorSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var premiumManager: PremiumManager
    @State private var activeHelp: HelpTip?
    @State private var showPSKReporter = false
    @State private var showPaywall = false

    private var pskReporterURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "pskreporter.info"
        components.path = "/pskmap.html"
        components.queryItems = [
            URLQueryItem(name: "callsign", value: viewModel.callsign.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        return components.url ?? URL(string: "https://pskreporter.info/pskmap.html")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
                Text("Receiver Control")
                    .font(.headline)

                ToggleRow(
                    labelKey: "Auto RX at start",
                    helpTip: .autoRXAtStart,
                    isOn: $viewModel.autoRXAtStart,
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_autoRXAtStart")

                Divider()

                Text("Auto CQ Reply")
                    .font(.headline)

                ToggleRow(
                    labelKey: "Reply to CQ received",
                    helpTip: .autoCQReply,
                    isOn: $viewModel.autoCQReplyEnabled,
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_autoCQReplyEnabled")

                ToggleRow(
                    labelKey: "Only if new band/mode",
                    helpTip: .autoCQNewBandMode,
                    isOn: $viewModel.autoCQReplyOnlyNewBandMode,
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_autoCQReplyOnlyNewBandMode")

                Divider()

                Text("Display & Transmission")
                    .font(.headline)

                ToggleRow(
                    labelKey: "Show TX messages in RX list",
                    helpTip: .decodeSelfTX,
                    isOn: $viewModel.decodeSelfTXMessages,
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_decodeSelfTXMessages")

                ToggleRow(
                    labelKey: "Hold TX frequency",
                    helpTip: .holdTXFrequency,
                    isOn: $viewModel.holdTXFrequency,
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_holdTXFrequency")

                Divider()

                Text("QSO Automation")
                    .font(.headline)

                ToggleRow(
                    labelKey: "Auto-sequence",
                    helpTip: .autoSequencing,
                    isOn: $viewModel.autoSequencingEnabled,
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_autoSequencingEnabled")

                RetrySlotsField(retries: $viewModel.maxRetrySlots)
                    .accessibilityIdentifier("field_maxRetrySlots")

                ToggleRow(
                    labelKey: "Auto QSO logging",
                    helpTip: .autoQSOLogging,
                    isOn: $viewModel.autoQSOLogging,
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_autoQSOLogging")

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("PSK reporter integration")
                        .font(.headline)

                    ToggleRow(
                        labelKey: "PSK Reporter",
                        helpTip: .pskReporter,
                        isOn: $viewModel.pskReporterEnabled,
                        activeHelp: $activeHelp
                    )
                    .accessibilityIdentifier("toggle_pskReporterEnabled")

                    Button("View on PSK Reporter →") {
                        showPSKReporter = true
                    }
                    .foregroundColor(.blue)
                    .accessibilityIdentifier("button_viewOnPSKReporter")
                }
                .opacity(premiumManager.isPremiumUnlocked ? 1.0 : 0.4)
                .disabled(!premiumManager.isPremiumUnlocked)
                .overlay {
                    if !premiumManager.isPremiumUnlocked {
                        Button {
                            showPaywall = true
                        } label: {
                            Color.clear
                        }
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("button_pskReporterLock")
                        .accessibilityLabel("PSK Reporter, Premium Feature")
                    }
                }
        }
        .onAppear { activeHelp = nil }
        .sheet(isPresented: $showPSKReporter) {
            SafariView(url: pskReporterURL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                PremiumPaywallView(source: "behavior_settings")
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
    }
}

struct BehaviorSettingsView: View {
    var body: some View {
        SettingsScrollContainer(
            title: "Behavior",
            alignment: .leading,
            spacing: 10,
            contentBottomPadding: 20,
            dismissKeyboardOnScroll: true
        ) {
            BehaviorSettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        BehaviorSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
