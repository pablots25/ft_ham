//
//  DisplaySettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

/// How decoded traffic is presented and how the operator interacts with it.
/// Nothing here changes what the app transmits.
struct DisplaySettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var activeHelp: HelpTip?
    @AppStorage("replyTapGesture") private var replyTapGesture: ReplyTapGesture = .single

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Message List")
                .font(.headline)

            VStack {
                Text("View mode:")
                Picker("View mode", selection: Binding(
                    get: { viewModel.selectedViewMode },
                    set: { newMode in
                        viewModel.selectedViewMode = newMode
                        AnalyticsManager.shared.trackViewMode(newMode)
                    }
                )) {
                    ForEach(ViewMode.allCases) { mode in
                        if !mode.isIPadOnly || UIDevice.current.userInterfaceIdiom == .pad {
                            Text(mode.textKey).tag(mode)
                        }
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("Choose how the TX/RX message list is displayed.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ToggleRow(
                labelKey: "Show TX messages in RX list",
                helpTip: .decodeSelfTX,
                isOn: $viewModel.decodeSelfTXMessages,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_decodeSelfTXMessages")

            ToggleRow(
                labelKey: "Highlight new callsigns",
                helpTip: .highlightNewCallsigns,
                isOn: $viewModel.highlightNewCallsigns,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_highlightNewCallsigns")

            ToggleRow(
                labelKey: "Show NEW GRID / NEW DXCC badges",
                helpTip: .neededBadges,
                isOn: $viewModel.showNeededBadges,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_showNeededBadges")

            Divider()

            Text("Interaction")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reply gesture")
                Picker("Reply gesture", selection: $replyTapGesture) {
                    ForEach(ReplyTapGesture.allCases) { gesture in
                        Text(gesture.label).tag(gesture)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("picker_replyTapGesture")

                Text("How tapping a decoded caller starts a reply. Double tap helps avoid accidental replies.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { activeHelp = nil }
    }
}

struct DisplaySettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Display", alignment: .leading, spacing: 10) {
            DisplaySettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        DisplaySettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
