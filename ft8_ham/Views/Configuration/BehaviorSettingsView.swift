//
//  BehaviorSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

struct BehaviorSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @StateObject private var premiumManager = PremiumManager.shared
    @FocusState private var retriesFocused: Bool
    @State private var activeHelp: HelpTip?
    @State private var showPSKReporter = false

    private var pskReporterURL: URL {
        var components = URLComponents(string: "https://pskreporter.info/pskmap")!
        components.queryItems = [
            URLQueryItem(name: "callsign", value: viewModel.callsign.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
        ]
        return components.url!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Receiver Control")
                    .font(.headline)

                ToggleRow(
                    labelKey: "Auto RX at start",
                    helpTip: .autoRXAtStart,
                    isOn: $viewModel.autoRXAtStart,
                    activeHelp: $activeHelp
                )

                Divider()

                Text("Auto CQ Reply")
                    .font(.headline)

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

                Divider()

                Text("Display & Transmission")
                    .font(.headline)

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

                Divider()

                Text("QSO Automation")
                    .font(.headline)

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

                if premiumManager.isPremiumUnlocked {
                    Text("PSK reporter integration")
                        .font(.headline)

                    ToggleRow(
                        labelKey: "PSK Reporter",
                        helpTip: .pskReporter,
                        isOn: $viewModel.pskReporterEnabled,
                        activeHelp: $activeHelp
                    )
                    Button("View on PSK Reporter →") {
                        showPSKReporter = true
                    }
                    .foregroundColor(.blue)
                    .padding(.bottom, 20)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .navigationTitle("Behavior")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { activeHelp = nil }
        .sheet(isPresented: $showPSKReporter) {
            SafariView(url: pskReporterURL)
                .ignoresSafeArea()
        }
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
