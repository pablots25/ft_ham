//
//  MessageView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//


import SwiftUI

struct MessageView: View {
    let msg: FT8Message
    var needed: NeededStatus = []
    /// Calling you or watched station: bold text and a marker.
    var highlight: RowHighlight = .none
    /// Show "(FT4)" / "(FT8)" when the row's mode differs from the current one.
    var showsMode: Bool = false
    /// The row belongs to the QSO in progress: draws a leading bar.
    var isActiveQSO: Bool = false

    var body: some View {
        if msg.msgType == .internalTimestamp {
            HStack {
                Spacer()
                Text(msg.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, DecodeRowMetrics.horizontalPadding)
        } else {
            // Metadata columns on top (aligned with the header), message below.
            VStack(alignment: .leading, spacing: 2) {
                DecodeRowColumns(msg: msg)

                DecodeRowMessage(
                    msg: msg,
                    needed: needed,
                    highlight: highlight,
                    showsMode: showsMode,
                    font: .caption,
                    forMeColor: .blue
                )
            }
            .padding(.horizontal, DecodeRowMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .activeQSOBar(isActiveQSO)
        }
    }
}

#Preview("MessageView") {
    VStack(spacing: 0) {
        MessageListHeaderView(allowReply: true)
        MessageView(msg: PreviewMocks.rxMessages[0])
        MessageView(msg: PreviewMocks.rxMessages[1], needed: [.dxcc, .grid], showsMode: true)
        MessageView(msg: PreviewMocks.rxMessages[0], highlight: .callingMe, isActiveQSO: true)
    }
    .frame(width: 393)
}
