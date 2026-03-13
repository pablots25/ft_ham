//
//  ModeFrequencyView.swift
//  ft_ham
//
//  Detail screen for Mode, Cycle, Band, Frequency, and Input Gain settings.
//  Extracted from ConfigurationView for Apple-standard NavigationLink pattern
//  and to reduce unnecessary re-renders on the root settings list.
//

import SwiftUI

struct ModeFrequencyView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel

    // Local state for debounced sliders (avoids per-frame @AppStorage writes)
    @State private var frequencyText: String = ""
    @State private var frequencySliderTemp: Double = 1500.0
    @State private var sliderTempValue: Float = 1.0

    private let minGain: Float = 0.1
    private let maxGain: Float = 2.0

    private static let appLogger = AppLogger(category: "APP")

    private enum FocusField: Hashable { case frequency }
    @FocusState private var focusedInput: FocusField?

    // MARK: - Number formatter (shared static instance)

    private static let frequencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        return f
    }()

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                modeView
                cycleView
            } header: {
                Text("Mode")
            }

            Section {
                BandPickerView(
                    selectedBand: $viewModel.selectedBand,
                    isFT4: viewModel.isFT4
                )
            } header: {
                Text("Band")
            }

            Section {
                frequencyView
            } header: {
                Text("Frequency Offset")
            }

            Section {
                inputGainView
            } header: {
                Text("Input Gain")
            }
        }
        .navigationTitle("Mode and frequency")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            frequencyText = Self.frequencyFormatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? ""
            frequencySliderTemp = viewModel.frequency
            sliderTempValue = Float(viewModel.inputGain)
        }
        .onChange(of: viewModel.frequency) { newValue in
            frequencySliderTemp = newValue
            if focusedInput != .frequency {
                let newText = Self.frequencyFormatter.string(
                    from: NSNumber(value: newValue / 1000)
                ) ?? frequencyText
                if frequencyText != newText {
                    frequencyText = newText
                }
            }
        }
    }

    // MARK: - Commit helpers

    private func commitFrequencyText() {
        let formatter = Self.frequencyFormatter
        if let number = formatter.number(from: frequencyText) {
            let valueHz = min(max(0, number.doubleValue * 1000), 3000)
            viewModel.frequency = valueHz
            frequencySliderTemp = valueHz
            frequencyText = formatter.string(from: NSNumber(value: valueHz / 1000)) ?? frequencyText
            AnalyticsManager.shared.logConfigurationSaved()
        } else {
            frequencyText = formatter.string(
                from: NSNumber(value: viewModel.frequency / 1000)
            ) ?? frequencyText
        }
    }

    // MARK: - Subviews

    private var modeView: some View {
        HStack {
            Text("Mode:")
            Spacer()
            Picker("", selection: isFT4Binding) {
                Text("FT8").tag(false)
                Text("FT4").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }

    private var isFT4Binding: Binding<Bool> {
        Binding(
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
                    Self.appLogger.log(.info, "Mode changed to \(modeStr), current cycle: \(cycleStr)")
                }
            }
        )
    }

    private var cycleView: some View {
        HStack {
            Text("Cycle:")
            Spacer()
            Picker("", selection: evenCycleBinding) {
                if viewModel.isFT4 {
                    Text("0").tag(true)
                    Text("7.5").tag(false)
                } else {
                    Text("0/30").tag(true)
                    Text("15/45").tag(false)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }

    private var evenCycleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.evenCycle },
            set: { newValue in
                viewModel.evenCycle = newValue
                if viewModel.isFT4 {
                    let offset = newValue ? 0.0 : 7.5
                    Self.appLogger.log(.info, "FT4 cycle changed to \(newValue ? "even" : "odd") — offset: \(offset)s")
                } else {
                    let offset = newValue ? 0.0 : 15.0
                    Self.appLogger.log(.info, "FT8 cycle changed to \(newValue ? "even" : "odd") — offsets: \(offset)/\(offset + 30.0)s")
                }
            }
        )
    }

    private var frequencyView: some View {
        VStack {
            HStack {
                Text("Frequency offset:")
                Spacer()
                HStack(spacing: 0) {
                    TextField("Frequency", text: $frequencyText)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .focused($focusedInput, equals: .frequency)
                        .lineLimit(1)
                        .onSubmit { commitFrequencyText() }
                        .frame(width: 80)
                    Text("kHz")
                        .padding(5)
                }
            }

            HStack {
                Button {
                    viewModel.frequency = max(0, viewModel.frequency - 10)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text("Decrease frequency"))

                Slider(value: $frequencySliderTemp, in: 0.1 ... 3000, step: 10) { isEditing in
                    if !isEditing {
                        viewModel.frequency = frequencySliderTemp
                        frequencyText = Self.frequencyFormatter.string(
                            from: NSNumber(value: frequencySliderTemp / 1000)
                        ) ?? frequencyText
                        AnalyticsManager.shared.logConfigurationSaved()
                    }
                }

                Button {
                    viewModel.frequency = min(3000, viewModel.frequency + 10)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text("Increase frequency"))
            }
        }
    }

    private var inputGainView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Gain:")
                Spacer()
                Text(String(format: "%.2f×", sliderTempValue))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $sliderTempValue,
                in: Float(minGain)...Float(maxGain),
                onEditingChanged: { isEditing in
                    if !isEditing {
                        viewModel.inputGain = Double(sliderTempValue)
                    }
                }
            )
            .accentColor(.blue)
        }
    }
}

// MARK: - Preview

#Preview("ModeFrequencyView") {
    NavigationStack {
        ModeFrequencyView()
            .environmentObject(
                FT8ViewModel(
                    txMessages: PreviewMocks.txMessages,
                    rxMessages: PreviewMocks.rxMessages
                )
            )
    }
}
