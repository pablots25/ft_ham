//
//  CatSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 26/02/26.
//

import SwiftUI

struct CatSettingsView: View {
    @AppStorage("catEnabled") private var catEnabled = false
    @AppStorage("catHost") private var catHost = "127.0.0.1"
    @AppStorage("catPort") private var catPort = 4532
    @AppStorage("catPTTEnabled") private var catPTTEnabled = true
    @AppStorage("catSyncFrequency") private var catSyncFrequency = true
    @AppStorage("catApplyAudioOffset") private var catApplyAudioOffset = false

    @State private var isTesting = false
    @State private var testStatus: String = ""
    @State private var activeHelp: CatHelp?

    private let catController = PremiumFeatures.catController

    private enum CatHelp: Equatable {
        case tcpConnection
        case audioOffset

        var text: String {
            switch self {
            case .tcpConnection:
                return String(localized: "Uses rigctld (hamlib) over TCP.")
            case .audioOffset:
                return String(localized: "Apply audio offset adds the TX offset in Hz to the dial frequency.")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("CAT over TCP")
                    .font(.headline)

                Toggle("Enable CAT", isOn: $catEnabled)
                TextField("Host", text: $catHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", value: $catPort, format: .number)
                    .keyboardType(.numberPad)
                    .onChange(of: catPort) { newValue in
                        catPort = min(max(newValue, 1), 65_535)
                    }

                HStack {
                    Spacer()
                    HelpIconButton(helpHint: CatHelp.tcpConnection.text) {
                        activeHelp = (activeHelp == .tcpConnection) ? nil : .tcpConnection
                    }
                }

                if activeHelp == .tcpConnection {
                    HelpBubble(text: CatHelp.tcpConnection.text)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                        ))
                }

                Divider()

                Text("CAT actions")
                    .font(.headline)

                Toggle("Send PTT on TX", isOn: $catPTTEnabled)
                    .disabled(!catEnabled)
                Toggle("Sync rig frequency", isOn: $catSyncFrequency)
                    .disabled(!catEnabled)
                Toggle("Apply audio offset", isOn: $catApplyAudioOffset)
                    .disabled(!catEnabled || !catSyncFrequency)

                HStack {
                    Spacer()
                    HelpIconButton(helpHint: CatHelp.audioOffset.text) {
                        activeHelp = (activeHelp == .audioOffset) ? nil : .audioOffset
                    }
                }

                if activeHelp == .audioOffset {
                    HelpBubble(text: CatHelp.audioOffset.text)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                        ))
                }

                Divider()

                Text("Connection test")
                    .font(.headline)

                Button(isTesting ? String(localized: "Testing...") : String(localized: "Test connection")) {
                    testConnection()
                }
                .disabled(isTesting || catHost.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)

                if !testStatus.isEmpty {
                    Text(testStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("CAT Control")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testConnection() {
        let host = catHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }

        isTesting = true
        testStatus = ""

        Task {
            let response = await catController.getFrequency(host: host, port: UInt16(clamping: catPort))
            await MainActor.run {
                isTesting = false
                if response.success {
                    let result = response.response.isEmpty ? "OK" : response.response
                    testStatus = "OK: \(result)"
                } else {
                    testStatus = "Error: \(response.errorMessage ?? "Unknown")"
                }
            }
        }
    }
}

#Preview("CatSettingsView") {
    NavigationStack {
        CatSettingsView()
    }
}
