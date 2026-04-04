//
//  DebugSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

#if DEBUG
struct DebugSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @State private var showWhatsNew = false
    @State private var showPaywall = false
    @ObservedObject private var premiumManager = PremiumManager.shared

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

                Text("PSK Reporter")
                    .font(.headline)

                #if canImport(FTHamPremium)
                PSKReporterDebugView(isEnabled: viewModel.pskReporterEnabled, callsign: viewModel.callsign)
                #else
                PSKReporterDebugViewStub()
                #endif
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(premiumManager: PremiumManager.shared, source: "debug")
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
