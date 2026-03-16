//
//  QSOSettingsView.swift
//  ft_ham
//
//  Detail screen for QSO-related settings: auto-sequence, retries, toggles.
//  Extracted from ConfigurationView for Apple-standard NavigationLink pattern.
//

import SwiftUI

struct QSOSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var activeHelp: HelpTip?

    private enum FocusField: Hashable { case retries }
    @FocusState private var focusedInput: FocusField?

    var body: some View {
        Form {
            Section {
                ToggleRow(
                    labelKey: "Auto-sequence",
                    helpTip: .autoSequencing,
                    isOn: $viewModel.autoSequencingEnabled,
                    activeHelp: $activeHelp
                )

                HStack(spacing: 6) {
                    TextField("Retries", value: $viewModel.maxRetrySlots, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .focused($focusedInput, equals: .retries)
                        .lineLimit(1)
                        .frame(width: 50)
                    Text("Retries")
                        .font(.body)
                        .accessibilityLabel(Text("Retransmission retries"))
                        .accessibilityHint(Text("Number of times to resend messages if not acknowledged"))
                }

                ToggleRow(
                    labelKey: "Auto QSO logging",
                    helpTip: .autoQSOLogging,
                    isOn: $viewModel.autoQSOLogging,
                    activeHelp: $activeHelp
                )
            } header: {
                Text("Sequencing")
            }

            Section {
                ToggleRow(
                    labelKey: "Auto RX at start",
                    helpTip: .autoRXAtStart,
                    isOn: $viewModel.autoRXAtStart,
                    activeHelp: $activeHelp
                )

                ToggleRow(
                    labelKey: "Reply to CQ received",
                    helpTip: .autoCQReply,
                    isOn: $viewModel.autoCQReplyEnabled,
                    activeHelp: $activeHelp
                )

                ToggleRow(
                    labelKey: "Only if new band/mode",
                    helpTip: .autoCQNewBandMode,
                    isOn: $viewModel.autoCQReplyOnlyNewBandMode,
                    activeHelp: $activeHelp
                )

                ToggleRow(
                    labelKey: "Show TX messages in RX list",
                    helpTip: .decodeSelfTX,
                    isOn: $viewModel.decodeSelfTXMessages,
                    activeHelp: $activeHelp
                )

                ToggleRow(
                    labelKey: "Hold TX frequency",
                    helpTip: .holdTXFrequency,
                    isOn: $viewModel.holdTXFrequency,
                    activeHelp: $activeHelp
                )
            } header: {
                Text("Behavior")
            }
        }
        .navigationTitle("QSO settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview("QSOSettingsView") {
    NavigationStack {
        QSOSettingsView()
            .environmentObject(
                FT8ViewModel(
                    txMessages: PreviewMocks.txMessages,
                    rxMessages: PreviewMocks.rxMessages
                )
            )
    }
}
