//
//  CondensedMsgView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - CondensedMsgView

struct CondensedMsgView: View {
    let msg: FT8Message
    var needed: NeededStatus = []
    /// Calling you or watched station: bold text and a marker.
    var highlight: RowHighlight = .none
    /// Show "(FT4)" / "(FT8)" when the row's mode differs from the current one.
    var showsMode: Bool = false
    /// The row belongs to the QSO in progress: draws a leading bar.
    var isActiveQSO: Bool = false

    private var metrics = DecodeRowMetrics()

    init(
        msg: FT8Message,
        needed: NeededStatus = [],
        highlight: RowHighlight = .none,
        showsMode: Bool = false,
        isActiveQSO: Bool = false
    ) {
        self.msg = msg
        self.needed = needed
        self.highlight = highlight
        self.showsMode = showsMode
        self.isActiveQSO = isActiveQSO
    }

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
            .background(Color(UIColor.systemBackground).opacity(0.001))
        } else {
            // One line: fixed-width metadata columns, then the message column,
            // which takes the rest of the width.
            HStack(alignment: .firstTextBaseline, spacing: metrics.columnSpacing) {
                DecodeRowColumns(msg: msg)

                DecodeRowMessage(
                    msg: msg,
                    needed: needed,
                    highlight: highlight,
                    showsMode: showsMode,
                    font: .caption,
                    forMeColor: Color.blue.opacity(0.85)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DecodeRowMetrics.horizontalPadding)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .activeQSOBar(isActiveQSO)
            .background(Color(UIColor.systemBackground).opacity(0.001))
        }
    }
}

#Preview("CondensedMsgView") {
    VStack(spacing: 0) {
        MessageListHeaderView(allowReply: true)
        CondensedMsgView(msg: PreviewMocks.rxMessages[0])
        CondensedMsgView(msg: PreviewMocks.rxMessages[1], needed: [.dxcc, .grid], showsMode: true)
        CondensedMsgView(msg: PreviewMocks.rxMessages[0], highlight: .callingMe, isActiveQSO: true)
        CondensedMsgView(msg: PreviewMocks.rxMessages[2])
    }
    .frame(width: 393)
}
