//
//  DebugSettingsView.swift
//  ft_ham
//

import SwiftUI

#if DEBUG
struct DebugSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var showWhatsNew = false
    @State private var showPaywall = false
    @AppStorage("debugUseNewConfigView") private var debugUseNewConfigView: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Use new config view", isOn: $debugUseNewConfigView)

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
            .padding(.horizontal)
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
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
    }
}
#endif
