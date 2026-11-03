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
                // WSPR beacons pick their slots at random, so there is no cycle to choose.
                if viewModel.digitalMode.supportsQSO {
                    cycleView
                }
            }
            .frame(maxWidth: .infinity)

            if viewModel.digitalMode == .wspr {
                wsprBeaconView
            }

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
        // WSPR beacons pick slots at random; the picker is hidden in that mode.
        case .wspr: return ("0/4/8", "2/6/10")
        }
    }

    // MARK: - WSPR beacon

    /// Reported power and share of slots used for TX.
    private var wsprBeaconView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WSPR power:")
                Spacer()
                Picker("WSPR power", selection: $viewModel.wsprPowerDBm) {
                    ForEach(WSPRSupport.validPowerLevels, id: \.self) { dbm in
                        Text(Self.wsprPowerLabel(dbm)).tag(dbm)
                    }
                }
                .pickerStyle(.menu)
            }
            HStack {
                Text("Beacon TX slots:")
                Spacer()
                Picker("Beacon TX slots", selection: $viewModel.wsprTxPercent) {
                    ForEach([0, 10, 20, 25, 33, 50], id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Beacon: \(viewModel.wsprBeaconMessage)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "37 dBm · 5 W" style label.
    static func wsprPowerLabel(_ dbm: Int) -> String {
        let watts = pow(10, Double(dbm - 30) / 10)
        let wattsText: String
        if watts >= 1 {
            wattsText = String(format: "%.0f W", watts)
        } else {
            wattsText = String(format: "%.0f mW", watts * 1000)
        }
        return "\(dbm) dBm · \(wattsText)"
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
