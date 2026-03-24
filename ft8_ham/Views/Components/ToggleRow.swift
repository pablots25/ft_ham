//
//  ToggleRow.swift
//  ft_ham
//

import SwiftUI

// MARK: - HelpTip Enum (Fallback for iOS 16)

enum HelpTip: Identifiable {
    case autoRXAtStart
    case autoCQReply
    case autoCQNewBandMode
    case decodeSelfTX
    case holdTXFrequency
    case autoSequencing
    case autoQSOLogging
    case analytics
    case locatorGPS
    case pskReporter
    case cqIncludeGrid
    case snrExplained
    case dtExplained
    case audioFrequencyHz
    case audioGain

    var id: Self { self }

    var text: String {
        switch self {
        case .autoRXAtStart:
            return String(localized: "Auto RX help")
        case .autoCQReply:
            return String(localized: "Auto CQ Reply help")
        case .autoCQNewBandMode:
            return String(localized: "Auto CQ New Band Mode help")
        case .decodeSelfTX:
            return String(localized: "Decode Self TX help")
        case .holdTXFrequency:
            return String(localized: "Hold TX Frequency help")
        case .autoSequencing:
            return String(localized: "Auto Sequencing help")
        case .autoQSOLogging:
            return String(localized: "Auto QSO Logging help")
        case .analytics:
            return String(localized: "Analytics help")
        case .locatorGPS:
            return String(localized: "Auto Locator help")
        case .pskReporter:
            return String(localized: "PSK Reporter help")
        case .cqIncludeGrid:
            return String(localized: "Include Grid in CQ help")
        case .snrExplained:
            return String(localized: "SNR dB help")
        case .dtExplained:
            return String(localized: "DT offset help")
        case .audioFrequencyHz:
            return String(localized: "Audio Frequency help")
        case .audioGain:
            return String(localized: "Audio Gain help")
        }
    }

    var accessibilityHint: String {
        text
    }
}

// MARK: - Toggle Row Component

struct ToggleRow: View, Equatable {
    let labelKey: LocalizedStringKey
    let helpTip: HelpTip
    @Binding var isOn: Bool
    @Binding var activeHelp: HelpTip?

    
    static func == (lhs: ToggleRow, rhs: ToggleRow) -> Bool {
        lhs.labelKey == rhs.labelKey &&
        lhs.helpTip == rhs.helpTip &&
        lhs.isOn == rhs.isOn &&
        lhs.activeHelp == rhs.activeHelp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .accessibilityLabel(Text(labelKey))
                    .accessibilityHint(Text(helpTip.accessibilityHint))

                Text(labelKey)
                    .font(.body)
                    .lineLimit(2)

                Spacer()

                HelpIconButton(helpHint: helpTip.accessibilityHint) {
                        activeHelp = (activeHelp == helpTip) ? nil : helpTip
                }
            }

            if activeHelp == helpTip {
                HelpBubble(text: helpTip.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
    }
}

struct HelpIconButton: View {
    let helpHint: String
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
                action()
            }
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .accessibilityLabel(Text("Help"))
        .accessibilityHint(Text(helpHint))
    }
}

// MARK: - Help Bubble

struct HelpBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(8)
    }
}
