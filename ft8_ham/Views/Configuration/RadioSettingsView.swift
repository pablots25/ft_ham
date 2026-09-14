//
//  RadioSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

struct RadioSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    private let appLogger = AppLogger(category: "APP")

    @FocusState private var frequencyFocused: Bool
    @State private var frequencyText: String = ""
    /// Local slider value; committed to the view model on release so a drag does
    /// not write UserDefaults (and publish the whole view model) on every tick.
    @State private var frequencySliderValue: Double = 1500
    /// RX gain slider position, in dB. The slider works in dB (not in the raw
    /// linear multiplier) so the attenuation end gets as much travel as the
    /// boost end: an external sound card feeds line level straight in and needs
    /// to be pulled down by tens of dB, which on a linear 0.01…2.0 scale would
    /// all be squeezed into the first few points of the track.
    @State private var inputGainDb: Float = 0
    @State private var txSliderTempValue: Float = 1.0
    @State private var activeHelp: HelpTip?
    @ObservedObject private var clockSync = ClockSyncManager.shared

    private let minInputGain = Float(AudioGainLimits.minInput)
    private let maxInputGain = Float(AudioGainLimits.maxInput)
    private let minOutputGain = Float(AudioGainLimits.minOutput)
    private let maxOutputGain = Float(AudioGainLimits.maxOutput)

    private var minInputGainDb: Float { Self.decibels(from: minInputGain) }
    private var maxInputGainDb: Float { Self.decibels(from: maxInputGain) }

    /// Linear multiplier -> dB.
    private static func decibels(from gain: Float) -> Float {
        20 * log10(max(gain, 0.0001))
    }

    /// dB -> linear multiplier.
    private static func linearGain(from decibels: Float) -> Float {
        pow(10, decibels / 20)
    }

    private static let frequencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        return f
    }()

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
            Text("Frequency offset and audio levels")
                .font(.headline)

            frequencyView

            inputGainView

            txOutputGainView

            Text("RX Gain: adjust microphone sensitivity for decoding. TX Output: raise if your radio's VOX won't activate (also ensure phone volume is at maximum).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()
            Text("Clock")
                .font(.headline)

            clockSyncView
        }
        .onAppear {
            frequencyText = Self.frequencyFormatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? ""
            inputGainDb = Self.decibels(from: Float(viewModel.inputGain))
            txSliderTempValue = Float(viewModel.txOutputGain)
            frequencySliderValue = viewModel.frequency
            activeHelp = nil
        }
        .onChange(of: viewModel.frequency) { newValue in
            if frequencySliderValue != newValue { frequencySliderValue = newValue }
            if !frequencyFocused {
                let newText = Self.frequencyFormatter.string(
                    from: NSNumber(value: newValue / 1000)
                ) ?? frequencyText
                if frequencyText != newText { frequencyText = newText }
            }
            if newValue > 0 { AnalyticsManager.shared.logConfigurationSaved() }
        }
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

    // MARK: - Frequency offset

    private var frequencyView: some View {
        VStack {
            HStack {
                Text("Frequency offset:")

                Spacer()
                HStack(spacing: 0) {
                    TextField("Frequency", text: $frequencyText)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .settingsCenteredInput()
                        .focused($frequencyFocused)
                        .onSubmit { commitFrequencyText() }
                        .frame(width: 80)
                    Text("kHz").padding(5)
                }
                HelpIconButton(helpHint: HelpTip.audioFrequencyHz.accessibilityHint) {
                    activeHelp = (activeHelp == .audioFrequencyHz) ? nil : .audioFrequencyHz
                }
            }

            if activeHelp == .audioFrequencyHz {
                HelpBubble(text: HelpTip.audioFrequencyHz.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }

            HStack {
                Button {
                    viewModel.frequency = max(0, viewModel.frequency - 10)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text("Decrease audio frequency"))

                Slider(
                    value: $frequencySliderValue,
                    in: 0.1...3000,
                    step: 10,
                    onEditingChanged: { isEditing in
                        if !isEditing { viewModel.frequency = frequencySliderValue }
                    }
                )

                Button {
                    viewModel.frequency = min(3000, viewModel.frequency + 10)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text("Increase audio frequency"))
            }
        }
    }

    // MARK: - Input gain

    private var inputGainView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Gain:")

                Spacer()
                Text(String(format: "%+.0f dB (%.2f×)",
                            inputGainDb,
                            Self.linearGain(from: inputGainDb)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                HelpIconButton(helpHint: HelpTip.audioGain.accessibilityHint) {
                    activeHelp = (activeHelp == .audioGain) ? nil : .audioGain
                }
            }

            if activeHelp == .audioGain {
                HelpBubble(text: HelpTip.audioGain.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }

            Slider(
                value: $inputGainDb,
                in: minInputGainDb...maxInputGainDb,
                step: 1,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    let linear = Self.linearGain(from: inputGainDb)
                    viewModel.inputGain = Double(
                        min(max(linear, minInputGain), maxInputGain)
                    )
                }
            )
        }
    }

    // MARK: - TX output gain

    private var txOutputGainView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TX Output Gain:")

                Spacer()
                Text(String(format: "%.2f×", txSliderTempValue))
                    .foregroundStyle(.secondary)
                HelpIconButton(helpHint: HelpTip.txOutputGain.accessibilityHint) {
                    activeHelp = (activeHelp == .txOutputGain) ? nil : .txOutputGain
                }
            }

            if activeHelp == .txOutputGain {
                HelpBubble(text: HelpTip.txOutputGain.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }

            Slider(
                value: $txSliderTempValue,
                in: minOutputGain...maxOutputGain,
                onEditingChanged: { isEditing in
                    if !isEditing { viewModel.txOutputGain = Double(txSliderTempValue) }
                }
            )
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

    // MARK: - Frequency commit

    private func commitFrequencyText() {
        let formatter = Self.frequencyFormatter
        if let number = formatter.number(from: frequencyText) {
            let valueHz = min(max(0, number.doubleValue * 1000), 3000)
            viewModel.frequency = valueHz
            frequencyText = formatter.string(from: NSNumber(value: valueHz / 1000)) ?? frequencyText
        } else {
            frequencyText = formatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? frequencyText
        }
    }
}

struct RadioSettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Radio", spacing: 20, dismissKeyboardOnScroll: true) {
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
