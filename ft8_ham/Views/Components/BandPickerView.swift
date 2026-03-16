//
//  BandPickerView.swift
//  ft_ham
//
//  Extracted from ConfigurationView for performance:
//  only re-renders when selectedBand or isFT4 change,
//  not on every FT8ViewModel @Published update.
//

import SwiftUI

/// Standalone band picker that only observes `selectedBand` and `isFT4`
/// via bindings, avoiding unnecessary re-renders from unrelated ViewModel changes.
struct BandPickerView: View {
    @Binding var selectedBand: FT8Message.Band
    let isFT4: Bool

    private var mode: FT8Message.FT8MessageMode { isFT4 ? .ft4 : .ft8 }
    private var bands: [FT8Message.Band] { FT8Message.Band.validBands }

    private var frequencyLabel: String {
        guard let hz = selectedBand.frequency(for: mode) else {
            return "— " + String(localized: "MHz")
        }
        return String(format: "%.3f ", hz / 1_000_000) + String(localized: "MHz")
    }

    private var selectedIndex: Int? {
        bands.firstIndex(of: selectedBand)
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
            }
        }
    }
}
