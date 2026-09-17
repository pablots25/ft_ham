//
//  RadioSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

/// Operating mode, TX cycle, band and the clock the slots run on. Audio
/// levels and the TX audio offset live in `AudioSettingsContent`.
struct RadioSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    private let appLogger = AppLogger(category: "APP")

    @State private var activeHelp: HelpTip?
    @ObservedObject private var clockSync = ClockSyncManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Mode and frequency")
                .font(.headline)

            HStack(spacing: 20) {
                modeView
                cycleView
            }
            .frame(maxWidth: .infinity)

            Text("Select operating mode and transmission cycle timing.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Text("Band")
                .font(.headline)

            BandPickerView(
                selectedBand: $viewModel.selectedBand,
                isFT4: viewModel.isFT4,
                customDialFrequencyHz: $viewModel.customDialFrequencyHz
            )

            Divider()
            Text("Clock")
                .font(.headline)

            clockSyncView
        }
        .onAppear { activeHelp = nil }
    }

    // MARK: - Mode picker

    private var modeView: some View {
        VStack {
            Text("Mode:")
            Picker("", selection: Binding(
                get: { viewModel.isFT4 },
                set: { newValue in
                    Task { @MainActor in
                        viewModel.switchModeWhileRX(isFT4: newValue)
                        AnalyticsManager.shared.trackRadioModeChange(isFT4: newValue)
                        let modeStr = newValue ? "FT4" : "FT8"
                        let cycleStr: String
                        if newValue {
                            cycleStr = viewModel.evenCycle ? "even (0s)" : "odd (7.5s)"
                        } else {
                            cycleStr = viewModel.evenCycle ? "even (0/30s)" : "odd (15/45s)"
                        }
                        appLogger.log(.info, "Mode changed to \(modeStr), current cycle: \(cycleStr)")
                    }
                }
            )) {
                Text("FT8").tag(false)
                Text("FT4").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    // MARK: - Cycle picker

    private var cycleView: some View {
        VStack {
            Text("Transmission cycle:")
            Picker("", selection: Binding(
                get: { viewModel.evenCycle },
                set: { newValue in
                    viewModel.evenCycle = newValue
                    if viewModel.isFT4 {
                        let offset = newValue ? 0.0 : 7.5
                        appLogger.log(.info, "FT4 cycle changed to \(newValue ? "even" : "odd") — offset: \(offset)s")
                    } else {
                        let offset = newValue ? 0.0 : 15.0
                        appLogger.log(.info, "FT8 cycle changed to \(newValue ? "even" : "odd") — offsets: \(offset)/\(offset + 30.0)s")
                    }
                }
            )) {
                if viewModel.isFT4 {
                    Text("0").tag(true)
                    Text("7.5").tag(false)
                } else {
                    Text("0/30").tag(true)
                    Text("15/45").tag(false)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    // MARK: - Clock sync

    @ViewBuilder
    private var clockSyncView: some View {
        ToggleRow(
            labelKey: "Sync clock with NTP",
            helpTip: .ntpSync,
            isOn: Binding(
                get: { clockSync.isEnabled },
                set: { clockSync.isEnabled = $0 }
            ),
            activeHelp: $activeHelp
        )
        .accessibilityIdentifier("toggle_ntpSyncEnabled")

        if clockSync.isEnabled {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let error = clockSync.lastError {
                        Text("Clock sync failed; using the device clock")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let date = clockSync.lastSyncDate {
                        Text(String(
                            format: String(localized: "Device clock offset: %@ s"),
                            String(format: "%+.3f", clockSync.offset)
                        ))
                        .foregroundStyle(clockSync.isWarning ? .red : .primary)
                        Text(String(
                            format: String(localized: "Last sync %@"),
                            date.formatted(date: .omitted, time: .standard)
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Not synced yet")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)

                Spacer()

                Button {
                    Task { await clockSync.syncNow() }
                } label: {
                    if clockSync.isSyncing {
                        ProgressView()
                    } else {
                        Text("Sync now")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(clockSync.isSyncing)
                .accessibilityLabel(Text("Sync now"))
                .accessibilityIdentifier("button_ntpSyncNow")
            }
            if clockSync.isWarning && clockSync.lastError == nil {
                Text("Your device clock is more than 1 s off. FT8 needs accurate time: enable Set Automatically in Settings > General > Date & Time.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct RadioSettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Mode & Band", spacing: 20, dismissKeyboardOnScroll: true) {
            RadioSettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        RadioSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
