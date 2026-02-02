//
//  GenMessagesView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - Generator of messages View

struct GenMessagesView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @FocusState private var focusedField: Bool

    // These must be updated onAppear to reflect initial ViewModel state
    @State private var validCallsign = false
    @State private var validLocator = false

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .bottom) {
                // MARK: DX Callsign Input
                VStack {
                    Text("DX Callsign:")
                    TextField("", text: $viewModel.dxCallsign)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .frame(width: 120)
                        .keyboardType(.asciiCapable)
                        .focused($focusedField)
                        .onChange(of: viewModel.dxCallsign) { newValue in
                            cleanAndValidateCallsign(newValue)
                        }
                }

                // MARK: DX Locator Input
                VStack {
                    Text("DX Locator:")
                        .frame(minWidth: 120)
                    TextField("", text: $viewModel.dxLocator)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .frame(width: 80)
                        .keyboardType(.asciiCapable)
                        .focused($focusedField)
                        .onChange(of: viewModel.dxLocator) { newValue in
                            cleanAndValidateLocator(newValue)
                        }
                }

                // MARK: Generate Button
                Button("Generate") {
                    viewModel.allMessages = viewModel.generateMessages()
                    if viewModel.selectedMessageIndex == nil { viewModel.selectedMessageIndex = 0 }
                    hideKeyboard()
                }
                .buttonStyle(.borderedProminent)
                // The button is disabled if settings aren't loaded OR inputs are invalid
                .disabled(!viewModel.settingsLoaded || !validCallsign || !validLocator)
            }

            // MARK: Message List
            VStack(spacing: 8) {
                ForEach(viewModel.allMessages.indices, id: \.self) { index in
                    messageRow(index: index, text: $viewModel.allMessages[index])
                }
            }
            .padding(.horizontal, 50)
            .frame(maxWidth: 500)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // CRITICAL: Validate current values immediately when the view loads
            validateAll()
            
//            viewModel.allMessages = viewModel.generateMessages()
//            if viewModel.selectedMessageIndex == nil { viewModel.selectedMessageIndex = 0 }
        }
    }

    // MARK: - Helper Methods

    private func validateAll() {
        validCallsign = isValidCallsign(viewModel.dxCallsign)
        validLocator = isValidLocator(viewModel.dxLocator)
    }

    private func cleanAndValidateCallsign(_ value: String) {
        var text = value.uppercased()
        text.removeAll(where: { $0.isWhitespace })
        let allowed = text.filter { $0.isLetter || $0.isNumber || $0 == "/" }
        
        if allowed != viewModel.dxCallsign {
            viewModel.dxCallsign = allowed
        }
        validCallsign = isValidCallsign(allowed)
    }

    private func cleanAndValidateLocator(_ value: String) {
        var text = value.uppercased()
        text.removeAll(where: { $0.isWhitespace })
        if text.count > 4 {
            text = String(text.prefix(4))
        }
        
        if text != viewModel.dxLocator {
            viewModel.dxLocator = text
        }
        validLocator = isValidLocator(text)
    }

    @ViewBuilder
    private func messageRow(index: Int, text: Binding<String>) -> some View {
        HStack {
            Button(action: {
                viewModel.selectedMessageIndex = index
            }) {
                Image(systemName: viewModel.selectedMessageIndex == index ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Preview
#Preview("GenMessagesView") {
    GenMessagesView()
        .environmentObject(FT8ViewModel(txMessages: PreviewMocks.txMessages, rxMessages: PreviewMocks.rxMessages))
}
