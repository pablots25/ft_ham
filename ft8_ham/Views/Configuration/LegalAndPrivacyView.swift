//
//  LegalAndPrivacyView.swift
//  ft_ham
//

import SwiftUI
import SafariServices

struct LegalAndPrivacyView: View {
    @EnvironmentObject private var flags: FeatureFlagManager
    @State private var activeHelp: HelpTip?
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfUse = false
    @State private var showLicenses = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy & Analytics")
                    .font(.headline)

                ToggleRow(
                    labelKey: "Share usage statistics",
                    helpTip: .analytics,
                    isOn: Binding(
                        get: { AnalyticsManager.shared.isAnalyticsEnabled },
                        set: { AnalyticsManager.shared.isAnalyticsEnabled = $0 }
                    ),
                    activeHelp: $activeHelp
                )

                if flags.isEnabled(.showLogsView) {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("View app logs", systemImage: "doc.text")
                    }
                }

                Divider()

                Text("Legal Information")
                    .font(.headline)

                Button {
                    showLicenses = true
                } label: {
                    HStack {
                        Label("Licenses & EULA", systemImage: "doc.on.doc")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Button {
                    showPrivacyPolicy = true
                } label: {
                    HStack {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Button {
                    showTermsOfUse = true
                } label: {
                    HStack {
                        Label("Terms of Use", systemImage: "doc.plaintext")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Legal & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { activeHelp = nil }
        .sheet(isPresented: $showPrivacyPolicy) {
            SafariView(url: URL(string: "https://ftham.turrion.dev/privacy")!)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showTermsOfUse) {
            SafariView(url: URL(string: "https://ftham.turrion.dev/terms")!)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLicenses) {
            LicenseDialogView()
        }
    }


}

#Preview {
    NavigationStack {
        LegalAndPrivacyView()
            .environmentObject(FeatureFlagManager.shared)
    }
}
