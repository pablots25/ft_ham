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

    private let catController = CatRigController.shared

    var body: some View {
        Form {
            Section("CAT over TCP") {
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
                Text("Uses rigctld (hamlib) over TCP.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("CAT actions") {
                Toggle("Send PTT on TX", isOn: $catPTTEnabled)
                    .disabled(!catEnabled)
                Toggle("Sync rig frequency", isOn: $catSyncFrequency)
                    .disabled(!catEnabled)
                Toggle("Apply audio offset", isOn: $catApplyAudioOffset)
                    .disabled(!catEnabled || !catSyncFrequency)
                Text("Apply audio offset adds the TX offset in Hz to the dial frequency.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Connection test") {
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
