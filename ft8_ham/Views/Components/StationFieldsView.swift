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

    @FocusState private var isFocused: Bool

    /// Shown under the field while the text is not a usable callsign. Being told
    /// which rule was broken matters most for compound calls, where the limit is
    /// what the protocol can carry rather than anything about the call itself.
    private var errorMessage: LocalizedStringKey {
        let text = callsignText.uppercased()
        if text.count > CompoundCallsign.maxLength {
            return "A callsign can be at most 11 characters, modifier included"
        }
        if text.filter({ $0 == "/" }).count > 1 {
            return "Only one modifier is allowed (e.g. I/VE6XAD or VE6XAD/P)"
        }
        return "Enter a valid callsign (e.g. EA4IQL)"
    }

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
                    .keyboardType(.asciiCapable)
                    .lineLimit(1)
                    .focused($isFocused)
                    .accessibilityLabel(Text("Callsign"))
                    .onChange(of: callsignText) { newValue in
                        // Keep the field to characters a callsign can contain, so
                        // a stray space or a lowercase keyboard does not read as
                        // an invalid callsign.
                        let cleaned = newValue.uppercased().filter {
                            $0.isLetter || $0.isNumber || $0 == "/"
                        }
                        if cleaned != newValue { callsignText = cleaned }
                        validCallsign = isValidCallsign(cleaned)
                    }
                    .onChange(of: isFocused) { focused in
                        // Commit when the field is left, not only when Return is
                        // pressed: tapping elsewhere used to discard the entry.
                        if !focused { onCommit() }
                    }
                    .onSubmit { onCommit() }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(!validCallsign && !callsignText.isEmpty ? Color.red : Color.clear, lineWidth: 1)
                    )
            }
            if !validCallsign && !callsignText.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Travelling? Add a modifier: I/VE6XAD or VE6XAD/P")
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
