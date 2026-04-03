//
//  BandPickerView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

/// Standalone band picker that only observes `selectedBand` and `isFT4`
/// via bindings, avoiding unnecessary re-renders from unrelated ViewModel changes.
struct BandPickerView: View {
    @Binding var selectedBand: FT8Message.Band
    let isFT4: Bool
    @Binding var customDialFrequencyHz: Double

    @State private var customDialFrequencyText: String = ""

    private static let dialFrequencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    init(selectedBand: Binding<FT8Message.Band>, isFT4: Bool, customDialFrequencyHz: Binding<Double> = .constant(14_074_000)) {
        self._selectedBand = selectedBand
        self.isFT4 = isFT4
        self._customDialFrequencyHz = customDialFrequencyHz
    }

    private var mode: FT8Message.FT8MessageMode { isFT4 ? .ft4 : .ft8 }
    private var bands: [FT8Message.Band] { FT8Message.Band.validBands }
    private var isCustom: Bool { selectedBand == .custom }

    private var frequencyLabel: String {
        if isCustom {
            let detectedBand = FT8Message.Band.fromFrequency(customDialFrequencyHz)
            let detectedText = detectedBand != .unknown ? " · \(detectedBand.rawValue)" : ""
            return String(format: "%.3f MHz%@", customDialFrequencyHz / 1_000_000, detectedText)
        }
        guard let hz = selectedBand.frequency(for: mode) else {
            return "— " + String(localized: "MHz")
        }
        return String(format: "%.3f ", hz / 1_000_000) + String(localized: "MHz")
    }

    private var selectedIndex: Int? {
        bands.firstIndex(of: selectedBand)
    }

    private func commitCustomDialFrequency() {
        let formatter = Self.dialFrequencyFormatter
        if let number = formatter.number(from: customDialFrequencyText), number.doubleValue > 0 {
            customDialFrequencyHz = number.doubleValue * 1_000_000
            customDialFrequencyText = formatter.string(from: NSNumber(value: number.doubleValue)) ?? customDialFrequencyText
        } else {
            customDialFrequencyText = formatter.string(
                from: NSNumber(value: customDialFrequencyHz / 1_000_000)
            ) ?? customDialFrequencyText
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Band:")
                Text(frequencyLabel)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                HStack(spacing: 6) {
                    // Left arrow
                    Button {
                        guard let index = selectedIndex, index > 0 else { return }
                        let newBand = bands[index - 1]
                        withAnimation {
                            selectedBand = newBand
                            proxy.scrollTo(newBand, anchor: .center)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIndex == 0)
                    .accessibilityLabel(Text("Previous band"))

                    // Scrollable bands
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(bands, id: \.self) { band in
                                Button {
                                    withAnimation {
                                        selectedBand = band
                                        proxy.scrollTo(band, anchor: .center)
                                    }
                                } label: {
                                    Text(band.rawValue)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            band == selectedBand
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.2)
                                        )
                                        .foregroundColor(
                                            band == selectedBand
                                            ? .white
                                            : .primary
                                        )
                                        .clipShape(Capsule())
                                }
                                .id(band)
                                .accessibilityLabel(Text("\(band.rawValue) band"))
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    // Right arrow
                    Button {
                        guard let index = selectedIndex, index < bands.count - 1 else { return }
                        let newBand = bands[index + 1]
                        withAnimation {
                            selectedBand = newBand
                            proxy.scrollTo(newBand, anchor: .center)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIndex == bands.count - 1)
                    .accessibilityLabel(Text("Next band"))
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedBand, anchor: .center)
                    }
                }
                .onChange(of: selectedBand) { newBand in
                    withAnimation {
                        proxy.scrollTo(newBand, anchor: .center)
                    }
                }
                .onChange(of: isFT4) { _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedBand, anchor: .center)
                    }
                }
            }

            // Custom frequency input (shown when Custom band is selected)
            if isCustom {
                HStack(spacing: 8) {
                    Text("Dial freq:")
                        .foregroundStyle(.secondary)
                    TextField("e.g. 14.074", text: $customDialFrequencyText)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .onSubmit { commitCustomDialFrequency() }
                        .frame(width: 130)
                    Text("MHz")
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isCustom)
        .onAppear {
            customDialFrequencyText = Self.dialFrequencyFormatter.string(
                from: NSNumber(value: customDialFrequencyHz / 1_000_000)
            ) ?? ""
        }
    }
}
