//
//  MessageListHeaderView.swift
//  ft_ham
//

import SwiftUI

struct MessageListHeaderView: View {
    let allowReply: Bool
    @Binding var showOnlyInvolved: Bool
    @State private var activeHeaderHelp: HeaderHelp?

    enum HeaderHelp: Equatable {
        case snr, dt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Time")
                if allowReply {
                    HStack(spacing: 2) {
                        Text("dB")
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                activeHeaderHelp = (activeHeaderHelp == .snr) ? nil : .snr
                            }
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Help for dB"))
                    }
                    Text("Freq.")
                    HStack(spacing: 2) {
                        Text("Δt")
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                activeHeaderHelp = (activeHeaderHelp == .dt) ? nil : .dt
                            }
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Help for time offset"))
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if activeHeaderHelp == .snr {
                HelpBubble(text: HelpTip.snrExplained.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            } else if activeHeaderHelp == .dt {
                HelpBubble(text: HelpTip.dtExplained.text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
        .dynamicTypeSize(.medium ... .accessibility5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

}

// Enum representing the different transmission sections
enum TransmissionSection: Hashable {
    case received
    case transmitted

    /// Localized display name for the section
    var localizedName: LocalizedStringKey {
        switch self {
        case .received:
            return LocalizedStringKey("Received")
        case .transmitted:
            return LocalizedStringKey("Transmitted")
        }
    }

    /// Used for switch statements and comparisons
    var id: String {
        switch self {
        case .received:
            return "received"
        case .transmitted:
            return "transmitted"
        }
    }
}
