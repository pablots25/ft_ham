//
//  DebugSettingsView.swift
//  ft_ham
//

import SwiftUI

#if DEBUG
struct DebugSettingsView: View {
    @State private var showWhatsNew = false

    var body: some View {
        List {
            Group {
            Section {
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

                Button(role: .destructive) {
                    fatalError("Intentional debug crash for testing crash reporting")
                } label: {
                    Label("Crash reporter test", systemImage: "exclamationmark.triangle")
                }
            }
            }
            .padding(.horizontal)
        }
        .settingsFormStyle(title: "Debug")
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
    }
}

#Preview {
    NavigationStack {
        DebugSettingsView()
    }
}
#endif
