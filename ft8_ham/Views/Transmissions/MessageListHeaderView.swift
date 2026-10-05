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

    var body: some View {
        // Clamped outside the content, as in `DecodeRowColumns`, so the
        // @ScaledMetric widths see the clamped size.
        MessageListHeaderContent(allowReply: allowReply)
            .dynamicTypeSize(DecodeRowMetrics.typeSizeRange)
    }
}

private struct MessageListHeaderContent: View {
    let allowReply: Bool

    private var metrics = DecodeRowMetrics()

    init(allowReply: Bool) {
        self.allowReply = allowReply
    }

    var body: some View {
        HStack(spacing: metrics.columnSpacing) {
            Text("Time")
                .frame(width: metrics.timeWidth, alignment: .leading)
            // Own transmissions have no SNR or time offset, but the rows keep
            // those slots, so the titles keep them too and Freq. stays over
            // its column.
            Text("dB")
                .frame(width: metrics.snrWidth, alignment: .trailing)
                .opacity(allowReply ? 1 : 0)
                .accessibilityHidden(!allowReply)
            Text("Freq.")
                .frame(width: metrics.frequencyWidth, alignment: .trailing)
            Text("Δt")
                .frame(width: metrics.timeOffsetWidth, alignment: .trailing)
                .opacity(allowReply ? 1 : 0)
                .accessibilityHidden(!allowReply)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DecodeRowMetrics.horizontalPadding)
    }
}

/// Whether the Received and Transmitted lists fit side by side.
enum TransmissionSectionLayout: Equatable {
    case sideBySide
    /// One list at a time, picked with a segmented control.
    case single

    /// - Parameters:
    ///   - availableWidth: width for both lists and the gap between them.
    ///   - rowWidth: width a decode row needs at the current text size.
    ///   - spacing: gap between the two lists, divider included.
    init(availableWidth: CGFloat, rowWidth: CGFloat, spacing: CGFloat) {
        let columnWidth = (availableWidth - spacing) / 2
        self = columnWidth >= rowWidth ? .sideBySide : .single
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
