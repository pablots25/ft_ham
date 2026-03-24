//
//  InterfaceSettingsView.swift
//  ft_ham
//

import SwiftUI

struct InterfaceSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Transmission List Mode")
                    .font(.headline)

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

                Text("Choose how the TX/RX message list is displayed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Tutorials")
                    .font(.headline)

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

                Text("Re-display help messages or the initial onboarding tutorial.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Interface")
        .navigationBarTitleDisplayMode(.inline)
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
