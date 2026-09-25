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
    /// Whether the operator has opted in to 11 m / CB callsigns. When off, an
    /// 11 m-format entry is rejected and the error nudges towards the toggle.
    var isElevenMeterEnabled: Bool = false
    var onCommit: () -> Void

    @FocusState private var isFocused: Bool

    /// Whether the current entry is a valid, opted-in 11 m / CB callsign.
    private var isElevenMeterCallsign: Bool {
        validCallsign && isElevenMeterEnabled
            && CompoundCallsign.isElevenMeterFormat(callsignText)
    }

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
        // Looks like an 11 m call but the operator has not opted in.
        if !isElevenMeterEnabled && CompoundCallsign.isElevenMeterFormat(text) {
            return "This looks like an 11 m / CB callsign. Turn on \"11 m / CB callsign\" below to use it."
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
                        validCallsign = isValidStationCallsign(cleaned, allowElevenMeter: isElevenMeterEnabled)
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
            .onDisappear {
                // Backstop: on a fast tab switch or navigation pop the focus
                // change can be skipped, so a typed-but-uncommitted call would be
                // lost. Committing here guarantees it is saved on the way out.
                onCommit()
            }
            if !validCallsign && !callsignText.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if isElevenMeterCallsign {
                Text("This is not a standard FT8/FT4 amateur callsign. It is sent as a non-standard callsign, and FT8/FT4 on the 11 m band may not be permitted where you operate.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
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

    @FocusState private var isFocused: Bool

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
                    .focused($isFocused)
                    .accessibilityLabel(Text("Grid locator"))
                    .onChange(of: locatorText) { newValue in
                        validLocator = isValidLocator(newValue.uppercased())
                    }
                    .onChange(of: isFocused) { focused in
                        // Commit on blur, not only on Return, mirroring the
                        // callsign field: tapping away used to discard the grid.
                        if !focused { onCommit() }
                    }
                    .onSubmit { onCommit() }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(!validLocator && !locatorText.isEmpty ? Color.red : Color.clear, lineWidth: 1)
                    )
            }
            .onDisappear {
                // Backstop for a skipped focus change on tab switch / pop, so a
                // typed-but-uncommitted grid is still saved on the way out.
                if !disabled { onCommit() }
            }
            if !validLocator && !locatorText.isEmpty {
                Text("Enter a valid 4-character grid (e.g. IN80)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
