//
//  DebugSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI
#if canImport(FTHamPremium)
import FTHamPremium
#endif

#if DEBUG
struct DebugSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @State private var showWhatsNew = false
    @State private var showPaywall = false
    @EnvironmentObject private var premiumManager: PremiumManager
    @State private var showMockDataLoaded = false

    var body: some View {
        SettingsScrollContainer(title: "Debug", alignment: .leading, spacing: 20) {
                Toggle(isOn: Binding(
                    get: { flags.isEnabled(.newConfigView) },
                    set: { flags.setOverride(.newConfigView, value: $0) }
                )) {
                    Label("New Config View", systemImage: "rectangle.3.group")
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { premiumManager.debugPremiumEnabled },
                    set: { premiumManager.setDebugPremium(enabled: $0) }
                )) {
                    Label("Premium Enabled", systemImage: "star.fill")
                }

                Divider()

                Button {
                    viewModel.loadMockData()
                    showMockDataLoaded = true
                } label: {
                    Label("Load Mock Data", systemImage: "tray.and.arrow.down.fill")
                }

                Divider()

                Button {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        InAppPrompts.shared.requestRate()
                    }
                } label: {
                    Label("Test Rate Prompt", systemImage: "star.fill")
                }

                Button {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        InAppPrompts.shared.showPreShareAlert = true
                    }
                } label: {
                    Label("Test Share Prompt", systemImage: "square.and.arrow.up")
                }

                Button {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        InAppPrompts.shared.showDonationAlert = true
                    }
                } label: {
                    Label("Test Donation Prompt", systemImage: "heart.fill")
                }

                Button {
                    showWhatsNew = true
                } label: {
                    Label("What's New", systemImage: "sparkles")
                }

                Button {
                    showPaywall = true
                } label: {
                    Label("Show Paywall", systemImage: "star.circle.fill")
                }

                Button(role: .destructive) {
                    fatalError("Intentional debug crash for testing crash reporting")
                } label: {
                    Label("Crash reporter test", systemImage: "exclamationmark.triangle")
                }

                Divider()

                NavigationLink {
                    LogsView()
                } label: {
                    Label("View app logs", systemImage: "doc.text")
                }

                Divider()

                Text("PSK Reporter")
                    .font(.headline)

                #if canImport(FTHamPremium)
                PSKReporterDebugView(isEnabled: viewModel.pskReporterEnabled, callsign: viewModel.callsign)
                #else
                PSKReporterDebugViewStub()
                #endif

                Divider()

                Text("CAT Control")
                    .font(.headline)

                #if canImport(FTHamPremium)
                CatDebugView()
                #else
                CatDebugViewStub()
                #endif
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(source: .screen("debug"))
        }
        .alert("Mock Data Loaded", isPresented: $showMockDataLoaded) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("RX messages, TX messages, and QSO log have been populated with sample data.")
        }
    }
}

#Preview {
    NavigationStack {
        DebugSettingsView()
            .environmentObject(FeatureFlagManager.shared)
    }
}
#endif
