//
//  WatchListEditor.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/09/26.
//

import SwiftUI

/// Add and remove the callsigns highlighted in the RX list (a DXpedition,
/// a friend). Stored through `FT8ViewModel.watchList`.
struct WatchListEditor: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var newCallsign = ""
    @State private var showInvalid = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Callsign", text: $newCallsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(add)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_watchCallsign")

                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(newCallsign.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("button_addWatchCallsign")
            }

            if showInvalid {
                Text("Enter a valid callsign that is not already on the list.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            let callsigns = viewModel.watchList.callsigns
            if callsigns.isEmpty {
                Text("No watched stations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(callsigns, id: \.self) { call in
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(RowColorStore.shared.color(.watched))
                            .accessibilityHidden(true)
                        Text(call)
                            .font(.body.monospaced())
                        Spacer()
                        Button {
                            viewModel.watchList.remove(call)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove \(call)"))
                    }
                    .accessibilityIdentifier("watchRow_\(call)")
                }
            }
        }
    }

    private func add() {
        var list = viewModel.watchList
        if list.add(newCallsign) {
            viewModel.watchList = list
            newCallsign = ""
            showInvalid = false
        } else {
            showInvalid = true
        }
    }
}
