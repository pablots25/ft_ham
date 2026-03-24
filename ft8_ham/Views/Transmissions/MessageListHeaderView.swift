//
//  MessageListHeaderView.swift
//  ft_ham
//

import SwiftUI

struct MessageListHeaderView: View {
    let allowReply: Bool
    @Binding var showOnlyInvolved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Time")
                if allowReply {
                    Text("dB")
                    Text("Freq.")
                    Text("Δt")
                }
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
