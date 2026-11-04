//
//  WaterfallSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 21/9/26.
//

import SwiftUI

/// How the waterfall levels and colours the spectrum. Applies immediately;
/// nothing here changes what is decoded or transmitted.
struct WaterfallSettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var settings = WaterfallDisplaySettings()
    @State private var activeHelp: HelpTip?
    @AppStorage("waterfallTapToReply") private var tapToReply = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Color")
                .font(.headline)

            paletteView

            Divider()

            Text("Level")
                .font(.headline)

            ToggleRow(
                labelKey: "Flatten passband",
                helpTip: .waterfallFlatten,
                isOn: $settings.flatten,
                activeHelp: $activeHelp
            )

            ToggleRow(
                labelKey: "Auto level",
                helpTip: .waterfallLevel,
                isOn: $settings.autoLevel,
                activeHelp: $activeHelp
            )

            if settings.autoLevel {
                sliderRow(
                    title: "Zero",
                    value: $settings.zeroDB,
                    range: WaterfallDisplaySettings.zeroRange,
                    step: 1,
                    format: { String(localized: "\($0, format: .number.precision(.fractionLength(0))) dB below noise") }
                )
            } else {
                sliderRow(
                    title: "Zero",
                    value: $settings.manualFloorDB,
                    range: WaterfallDisplaySettings.manualFloorRange,
                    step: 1,
                    format: { String(format: "%+.0f dB", $0) }
                )
            }

            sliderRow(
                title: "Gain",
                value: $settings.gainDB,
                range: WaterfallDisplaySettings.gainRange,
                step: 1,
                format: { String(localized: "\($0, format: .number.precision(.fractionLength(0))) dB range") }
            )

            Text("Zero is where the darkest color starts. Gain is how many dB the scale covers. Lower the gain to make weak signals stand out, raise it if strong ones saturate.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Reset to defaults") {
                settings = WaterfallDisplaySettings()
            }
            .font(.footnote)

            Divider()

            Text("Gestures")
                .font(.headline)

            ToggleRow(
                labelKey: "Tap a signal to reply",
                helpTip: .waterfallTapToReply,
                isOn: $tapToReply,
                activeHelp: $activeHelp
            )

            Text("With this off, a tap does nothing. Holding a signal still replies. To move the transmit frequency, turn on the frequency button first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            settings = viewModel.waterfallVM.displaySettings
            activeHelp = nil
        }
        .onChange(of: settings) { newValue in
            viewModel.waterfallVM.displaySettings = newValue
        }
    }

    // MARK: - Palette

    private var paletteView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Palette:")
                Spacer()
                HelpIconButton(helpHint: HelpTip.waterfallPalette.accessibilityHint) {
                    activeHelp = (activeHelp == .waterfallPalette) ? nil : .waterfallPalette
                }
            }

            if activeHelp == .waterfallPalette {
                HelpBubble(text: HelpTip.waterfallPalette.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }

            VStack(spacing: 6) {
                ForEach(WaterfallPalette.allCases) { palette in
                    Button {
                        settings.palette = palette
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(palette.gradient)
                                .frame(width: 120, height: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                                )
                            Text(palette.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.palette == palette {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("waterfallPalette_\(palette.rawValue)")
                    .accessibilityAddTraits(settings.palette == palette ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Sliders

    private func sliderRow(
        title: LocalizedStringKey,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        format: @escaping (Float) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

struct WaterfallSettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Waterfall", spacing: 20) {
            WaterfallSettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        WaterfallSettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
