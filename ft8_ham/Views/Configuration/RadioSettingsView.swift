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
                // Beacon modes pick their slots at random, so there is no cycle to choose.
                if viewModel.digitalMode.supportsQSO {
                    cycleView
                }
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
                mode: viewModel.digitalMode,
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
                get: { viewModel.digitalMode },
                set: { newMode in
                    Task { @MainActor in
                        viewModel.switchModeWhileRX(to: newMode)
                        AnalyticsManager.shared.trackRadioModeChange(newMode)
                        let labels = Self.cycleLabels(for: newMode)
                        let cycleStr = viewModel.evenCycle
                            ? "even (\(labels.even)s)"
                            : "odd (\(labels.odd)s)"
                        appLogger.log(.info, "Mode changed to \(newMode.displayName), current cycle: \(cycleStr)")
                    }
                }
            )) {
                ForEach(DigitalMode.selectableCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: DigitalMode.selectableCases.count > 3 ? 240 : 170)
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
                    let mode = viewModel.digitalMode
                    let labels = Self.cycleLabels(for: mode)
                    appLogger.log(.info, "\(mode.displayName) cycle changed to \(newValue ? "even" : "odd"), offsets: \(newValue ? labels.even : labels.odd)s")
                }
            )) {
                let labels = Self.cycleLabels(for: viewModel.digitalMode)
                Text(labels.even).tag(true)
                Text(labels.odd).tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    /// Picker labels (seconds within the minute) for the even/odd TX cycles.
    static func cycleLabels(for mode: DigitalMode) -> (even: String, odd: String) {
        switch mode {
        case .ft8: return ("0/30", "15/45")
        case .ft4: return ("0", "7.5")
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
                        Text("Clock sync failed, using the device clock")
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
