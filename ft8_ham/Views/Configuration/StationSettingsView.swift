//
//  StationSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

struct StationSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    private enum FocusField { case callsign, locator }
    @FocusState private var focusedInput: FocusField?

    @State private var callsignText: String = ""
    @State private var validCallsign = false
    @State private var validLocator = false
    @State private var activeHelp: HelpTip?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Station details")
                    .font(.headline)

                HStack {
                    Text("Callsign:")
                    TextField("", text: $callsignText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .focused($focusedInput, equals: .callsign)
                        .lineLimit(1)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: callsignText) { newValue in
                            validCallsign = isValidCallsign(newValue.uppercased())
                        }
                        .onSubmit { commitCallsign() }
                        .border(validCallsign ? Color.clear : Color.red)
                }

                Text("Callsign modifiers are allowed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Locator")
                    .font(.headline)

                HStack {
                    Text("Locator:")
                    Spacer()
                    TextField("", text: $viewModel.locator)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .focused($focusedInput, equals: .locator)
                        .lineLimit(1)
                        .disabled(viewModel.autoLocatorFromGPS)
                        .onChange(of: viewModel.locator) { newValue in
                            var text = newValue.uppercased()
                            text.removeAll(where: { $0.isWhitespace })
                            if text.count > 4 { text = String(text.prefix(4)) }
                            if text != viewModel.locator { viewModel.locator = text }
                            validLocator = isValidLocator(text)
                        }
                        .border(validLocator ? Color.clear : Color.red)
                }

                ToggleRow(
                    labelKey: "Auto (from GPS)",
                    helpTip: .locatorGPS,
                    isOn: Binding(
                        get: { viewModel.autoLocatorFromGPS },
                        set: { viewModel.setAutoLocatorFromGPS($0) }
                    ),
                    activeHelp: $activeHelp
                )

                ToggleRow(
                    labelKey: "Include Grid in CQ",
                    helpTip: .cqIncludeGrid,
                    isOn: $viewModel.cqIncludeGrid,
                    activeHelp: $activeHelp
                )

                Divider()

                Text("CQ Modifier")
                    .font(.headline)

                NewCQModifierView()
            }
            .padding(.horizontal)
        }
        .navigationTitle("Station")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            callsignText = viewModel.callsign
            validCallsign = isValidCallsign(viewModel.callsign)
            validLocator = isValidLocator(viewModel.locator)
            activeHelp = nil
        }
        .onChange(of: focusedInput) { newValue in
            // Commit callsign when leaving the callsign field (not just on full blur)
            if newValue != .callsign { commitCallsign() }
        }
        .onChange(of: viewModel.callsign) { newValue in
            let isValid = isValidCallsign(newValue)
            if validCallsign != isValid { validCallsign = isValid }
            if isValid && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
        .onChange(of: viewModel.locator) { newValue in
            let isValid = isValidLocator(newValue)
            if validLocator != isValid { validLocator = isValid }
            if isValid && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
    }

    private func commitCallsign() {
        let text = callsignText.uppercased()
        callsignText = text
        validCallsign = isValidCallsign(text)
        if validCallsign { viewModel.callsign = text }
    }
}

#Preview {
    NavigationStack {
        StationSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
