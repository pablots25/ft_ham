//
//  MessageListHeaderView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 02/02/26.
//

import SwiftUI

/// Column titles for the decode lists. Uses the same `DecodeRowMetrics` as the
/// rows so every title sits over its column.
struct MessageListHeaderView: View {
    let allowReply: Bool

    private var metrics = DecodeRowMetrics()

    init(allowReply: Bool) {
        self.allowReply = allowReply
    }

    var body: some View {
        HStack(spacing: metrics.columnSpacing) {
            Text("Time")
                .frame(width: metrics.timeWidth, alignment: .leading)
            if allowReply {
                Text("dB")
                    .frame(width: metrics.snrWidth, alignment: .trailing)
                Text("Freq.")
                    .frame(width: metrics.frequencyWidth, alignment: .trailing)
                Text("Δt")
                    .frame(width: metrics.timeOffsetWidth, alignment: .trailing)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .dynamicTypeSize(.medium ... .accessibility5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DecodeRowMetrics.horizontalPadding)
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
