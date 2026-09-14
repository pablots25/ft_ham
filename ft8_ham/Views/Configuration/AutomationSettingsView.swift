//
//  AutomationSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

/// Everything that decides what the app does on its own while operating:
/// receiver start-up, how it answers callers and how a QSO runs through to
/// the log. Presentation preferences live in
/// `DisplaySettingsContent`; network reporting in `ReportingSettingsContent`.
struct AutomationSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var activeHelp: HelpTip?

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
                labelKey: "Random caller in pile-ups",
                helpTip: .pileupRandom,
                isOn: $viewModel.pileupRandomCaller,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_pileupRandomCaller")

            ToggleRow(
                labelKey: "Prefer never-worked callers",
                helpTip: .pileupPreferNew,
                isOn: $viewModel.pileupPreferNewCallsigns,
                activeHelp: $activeHelp
            )
            .disabled(!viewModel.pileupRandomCaller)
            .opacity(viewModel.pileupRandomCaller ? 1.0 : 0.4)
            .accessibilityIdentifier("toggle_pileupPreferNewCallsigns")

            ToggleRow(
                labelKey: "Auto QSO logging",
                helpTip: .autoQSOLogging,
                isOn: $viewModel.autoQSOLogging,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_autoQSOLogging")

            Divider()

            Text("Transmission")
                .font(.headline)

            ToggleRow(
                labelKey: "Hold TX frequency",
                helpTip: .holdTXFrequency,
                isOn: $viewModel.holdTXFrequency,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_holdTXFrequency")
        }
        .onAppear { activeHelp = nil }
    }
}

struct AutomationSettingsView: View {
    var body: some View {
        SettingsScrollContainer(
            title: "Automation",
            alignment: .leading,
            spacing: 10,
            contentBottomPadding: 20,
            dismissKeyboardOnScroll: true
        ) {
            AutomationSettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        AutomationSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
