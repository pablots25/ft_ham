//
//  ToggleRow.swift
//  ft_ham
//

import SwiftUI

// MARK: - HelpTip Enum

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
    case cqIncludeGrid

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
        case .cqIncludeGrid:
            return String(localized: "Include Grid in CQ help")
        }
    }

    var accessibilityHint: String { text }
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

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
                        activeHelp = (activeHelp == helpTip) ? nil : helpTip
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .accessibilityLabel(Text("Help"))
                .accessibilityHint(Text(helpTip.accessibilityHint))
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

// MARK: - Help Bubble

struct HelpBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}
