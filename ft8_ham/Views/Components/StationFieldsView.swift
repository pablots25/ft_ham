//
//  StationFieldsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

// MARK: - Callsign Field

struct CallsignFieldView: View {
    @Binding var callsignText: String
    @Binding var validCallsign: Bool
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Callsign:")
                Spacer()
                TextField("", text: $callsignText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .lineLimit(1)
                    .accessibilityLabel(Text("Callsign"))
                    .onChange(of: callsignText) { newValue in
                        validCallsign = isValidCallsign(newValue.uppercased())
                    }
                    .onSubmit { onCommit() }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(!validCallsign && !callsignText.isEmpty ? Color.red : Color.clear, lineWidth: 1)
                    )
            }
            if !validCallsign && !callsignText.isEmpty {
                Text("Enter a valid callsign (e.g. EA4IQL)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Callsign modifiers are allowed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Locator Field

struct LocatorFieldView: View {
    @Binding var locatorText: String
    @Binding var validLocator: Bool
    var disabled: Bool = false
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Locator:")
                Spacer()
                TextField("", text: $locatorText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .disabled(disabled)
                    .accessibilityLabel(Text("Grid locator"))
                    .onChange(of: locatorText) { newValue in
                        validLocator = isValidLocator(newValue.uppercased())
                    }
                    .onSubmit { onCommit() }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(!validLocator && !locatorText.isEmpty ? Color.red : Color.clear, lineWidth: 1)
                    )
            }
            if !validLocator && !locatorText.isEmpty {
                Text("Enter a valid 4-character grid (e.g. IN80)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
