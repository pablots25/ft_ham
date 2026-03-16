//
//  InterfaceSettingsView.swift
//  ft_ham
//

import SwiftUI

struct InterfaceSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    var body: some View {
        List {
            Group {
            // MARK: - Transmission List Mode
            Section {
                VStack {
                    Text("View mode:")
                    Picker("View mode", selection: Binding(
                        get: { viewModel.selectedViewMode },
                        set: { newMode in
                            viewModel.selectedViewMode = newMode
                            AnalyticsManager.shared.trackViewMode(newMode)
                        }
                    )) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.textKey).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Transmission List Mode")
            } footer: {
                Text("Choose how the TX/RX message list is displayed.")
            }

            // MARK: - Tutorials
            Section {
                Button {
                    AppStorageResetter.resetTutorials()
                } label: {
                    Label("Reset help messages", systemImage: "arrow.counterclockwise")
                }

                Button {
                    AppStorageResetter.resetOnboarding()
                } label: {
                    Label("Show initial tutorial", systemImage: "play.circle")
                }
            } header: {
                Text("Tutorials")
            } footer: {
                Text("Re-display help messages or the initial onboarding tutorial.")
            }
            }
            .padding(.horizontal)
        }
        .settingsFormStyle(title: "Interface")
    }
}

#Preview {
    NavigationStack {
        InterfaceSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
