//
//  ReportingSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import SwiftUI

/// What the station shares with the outside world: PSK Reporter spots and
/// the operator's presence on the community map. Both are premium; the
/// row that leads here is locked for free users, so the content itself is
/// not gated.
struct ReportingSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var flags: FeatureFlagManager
    @ObservedObject private var presence = PresenceManager.shared
    @State private var activeHelp: HelpTip?
    @State private var showPSKReporter = false

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
            Text("PSK Reporter")
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

            if flags.isEnabled(.enablePresence) {
                Divider()

                Text("Community")
                    .font(.headline)

                ToggleRow(
                    labelKey: "Show me online on the map",
                    helpTip: .presence,
                    isOn: Binding(
                        get: { presence.optIn },
                        set: { presence.optIn = $0 }
                    ),
                    activeHelp: $activeHelp
                )
                .accessibilityIdentifier("toggle_presenceOptIn")
            }
        }
        .onAppear { activeHelp = nil }
        .sheet(isPresented: $showPSKReporter) {
            SafariView(url: pskReporterURL)
                .ignoresSafeArea()
        }
    }
}

struct ReportingSettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Reporting", alignment: .leading, spacing: 10) {
            ReportingSettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        ReportingSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
            .environmentObject(FeatureFlagManager.shared)
    }
}
