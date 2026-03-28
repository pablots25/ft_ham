//
//  RadioSettingsView.swift
//  ft_ham
//

import SwiftUI

struct RadioSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    private let appLogger = AppLogger(category: "APP")

    @FocusState private var frequencyFocused: Bool
    @State private var frequencyText: String = ""
    @State private var sliderTempValue: Float = 1.0
    @State private var activeHelp: HelpTip?

    private let minGain: Float = 0.1
    private let maxGain: Float = 2.0

    private static let frequencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                    isFT4: viewModel.isFT4
                )

                Divider()

                Text("Frequency offset")
                    .font(.headline)

                frequencyView

                Divider()

                Text("Input Gain")
                    .font(.headline)

                inputGainView

                Text("Adjust microphone input gain for optimal decoding.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Radio")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            frequencyText = Self.frequencyFormatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? ""
            sliderTempValue = Float(viewModel.inputGain)
        }
        .onChange(of: viewModel.frequency) { newValue in
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
                HelpIconButton(helpHint: HelpTip.audioFrequencyHz.accessibilityHint) {
                    activeHelp = (activeHelp == .audioFrequencyHz) ? nil : .audioFrequencyHz
                }
                Spacer()
                HStack(spacing: 0) {
                    TextField("Frequency", text: $frequencyText)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .focused($frequencyFocused)
                        .lineLimit(1)
                        .onSubmit { commitFrequencyText() }
                        .frame(width: 80)
                    Text("kHz").padding(5)
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

                Slider(value: $viewModel.frequency, in: 0.1...3000, step: 10)

                Button {
                    viewModel.frequency = min(3000, viewModel.frequency + 10)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Input gain

    private var inputGainView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Gain:")
                HelpIconButton(helpHint: HelpTip.audioGain.accessibilityHint) {
                    activeHelp = (activeHelp == .audioGain) ? nil : .audioGain
                }
                Spacer()
                Text(String(format: "%.2f×", sliderTempValue))
                    .foregroundStyle(.secondary)
            }

            if activeHelp == .audioGain {
                HelpBubble(text: HelpTip.audioGain.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }

            Slider(
                value: $sliderTempValue,
                in: Float(minGain)...Float(maxGain),
                onEditingChanged: { isEditing in
                    if !isEditing { viewModel.inputGain = Double(sliderTempValue) }
                }
            )
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

#Preview {
    NavigationStack {
        RadioSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
