//
//  StationSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

struct StationSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    @State private var callsignText: String = ""
    @State private var locatorText: String = ""
    @State private var validCallsign = false
    @State private var validLocator = false
    @State private var activeHelp: HelpTip?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Station details")
                .font(.headline)

            CallsignFieldView(
                callsignText: $callsignText,
                validCallsign: $validCallsign,
                onCommit: {
                    let text = callsignText.uppercased()
                    callsignText = text
                    validCallsign = isValidCallsign(text)
                    if validCallsign { viewModel.callsign = text }
                }
            )

            Divider()

            Text("Locator")
                .font(.headline)

            LocatorFieldView(
                locatorText: $locatorText,
                validLocator: $validLocator,
                disabled: viewModel.autoLocatorFromGPS,
                onCommit: {
                    var text = locatorText.uppercased()
                    text.removeAll(where: { $0.isWhitespace })
                    if text.count > 4 { text = String(text.prefix(4)) }
                    locatorText = text
                    if isValidLocator(text) { viewModel.locator = text }
                }
            )

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

            CQModifierView()
        }
        .onAppear {
            callsignText = viewModel.callsign
            locatorText = viewModel.locator
            validCallsign = isValidCallsign(viewModel.callsign)
            validLocator = isValidLocator(viewModel.locator)
            activeHelp = nil
        }
        .onChange(of: viewModel.callsign) { newValue in
            callsignText = newValue
            let isValid = isValidCallsign(newValue)
            if validCallsign != isValid { validCallsign = isValid }
            if isValid && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
        .onChange(of: viewModel.locator) { newValue in
            locatorText = newValue
            let isValid = isValidLocator(newValue)
            if validLocator != isValid { validLocator = isValid }
            if isValid && !newValue.isEmpty {
                AnalyticsManager.shared.logConfigurationSaved()
            }
        }
    }
}

struct StationSettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Station", spacing: 20, dismissKeyboardOnScroll: true) {
            StationSettingsContent()
        }
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
