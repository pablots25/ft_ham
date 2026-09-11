//
//  FreeTextTXView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import SwiftUI

/// Sheet to type a 13-character free-text message and loop it on every
/// my-turn slot until stopped.
struct FreeTextTXView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    private var text: String { viewModel.freeTextForTX }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("HELLO WORLD", text: Binding(
                        get: { viewModel.freeTextMessage },
                        set: { viewModel.freeTextMessage = FreeTextMessage.sanitize($0) }
                    ))
                    .font(.system(.title3, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .accessibilityIdentifier("field_freeText")

                    HStack {
                        Text("\(text.count)/\(FreeTextMessage.maxLength)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(text.count == FreeTextMessage.maxLength ? .orange : .secondary)
                        Spacer()
                        Text(slotParityText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Free Text")
                } footer: {
                    Text("Up to 13 characters: letters, digits, space and + - . / ?. Sent as-is on every one of your slots until you stop it. A free-text message does not carry your callsign — identify yourself regularly.")
                }

                Section {
                    Button {
                        viewModel.toggleFreeTextLoop()
                        if viewModel.freeTextLoopActive { dismiss() }
                    } label: {
                        Label(
                            viewModel.freeTextLoopActive ? "Stop loop" : "Start loop",
                            systemImage: viewModel.freeTextLoopActive ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.freeTextLoopActive ? .red : .blue)
                    .disabled(!viewModel.freeTextLoopActive && !viewModel.canStartFreeTextLoop)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("button_freeTextLoop")
                }
            }
            .navigationTitle("Free Text TX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton()
                }
            }
            .onAppear { fieldFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var slotParityText: String {
        switch viewModel.txSlotPreference {
        case .followClock:
            return viewModel.evenCycle ? String(localized: "Even slots") : String(localized: "Odd slots")
        case .forceEven:
            return String(localized: "Even slots")
        case .forceOdd:
            return String(localized: "Odd slots")
        }
    }
}

#Preview {
    FreeTextTXView()
        .environmentObject(FT8ViewModel())
}
