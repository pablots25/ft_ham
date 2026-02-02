//
//  MessageListHeaderView.swift
//  ft8_ham
//

import SwiftUI

struct MessageListHeaderView: View {
    let allowReply: Bool
    @Binding var showOnlyInvolved: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 25) {
                Text("Time")
                Text("dB")
                    .opacity(allowReply ? 1.0 : 0.0)
                Text("Freq.")
                Text("Δt")
                    .opacity(allowReply ? 1.0 : 0.0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
