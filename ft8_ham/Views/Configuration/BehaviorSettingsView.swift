//
//  BehaviorSettingsView.swift
//  ft_ham
//

import SwiftUI

struct BehaviorSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @FocusState private var retriesFocused: Bool
    @State private var activeHelp: HelpTip?

    var body: some View {
        List {
            Group {
            // MARK: - Receiver Control
            Section {
                ToggleRow(
                    labelKey: "Auto RX at start",
                    helpTip: .autoRXAtStart,
                    isOn: $viewModel.autoRXAtStart,
                    activeHelp: $activeHelp
                )
            } header: {
                Text("Receiver Control")
            }

            // MARK: - Auto CQ Reply
            Section {
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
            } header: {
                Text("Auto CQ Reply")
            }

            // MARK: - Display & Transmission
            Section {
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
                Text("Display & Transmission")
            }

            // MARK: - QSO Automation
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
                        .focused($retriesFocused)
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
                Text("QSO Automation")
            }
            }
            .padding(.horizontal)
        }
        .settingsFormStyle(title: "Behavior")
        .scrollDismissesKeyboard(.interactively)
        .onAppear { activeHelp = nil }
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
