//
//  AudioSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 17/09/26.
//

import SwiftUI

/// The audio path between the phone and the radio: TX audio offset within
/// the passband, microphone (RX) gain and TX output level.
struct AudioSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

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
    @StateObject private var deviceVolume = DeviceVolumeMonitor()

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
            Text("Frequency offset")
                .font(.headline)

            frequencyView

            Divider()

            Text("Audio levels")
                .font(.headline)

            inputGainView

            txOutputGainView

            Text("RX Gain: adjust microphone sensitivity for decoding. TX Output: raise if your radio's VOX won't activate (also ensure phone volume is at maximum).")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

            if deviceVolume.showsLowVolumeHint {
                Label {
                    Text("Device volume is below maximum. Turn it all the way up with the volume buttons so the TX audio is loud enough to trigger your radio's VOX.")
                } icon: {
                    Image(systemName: "speaker.wave.1.fill")
                }
                .font(.footnote)
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
        .animation(.default, value: deviceVolume.showsLowVolumeHint)
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

struct AudioSettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Audio", spacing: 20, dismissKeyboardOnScroll: true) {
            AudioSettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        AudioSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
