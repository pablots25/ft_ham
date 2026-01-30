//
//  CondensedMsgView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - CondensedMsgView

struct CondensedMsgView: View {
    let msg: FT8Message
    
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
            .padding(.horizontal, 5)
            .background(Color(UIColor.systemBackground).opacity(0.001))
        } else {
            HStack(alignment: .top, spacing: 10) {
                HStack(spacing: 15) {
                    Text(DateFormatter.utcFormatterClock.string(from: msg.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(!msg.measuredSNR.isNaN ? String(format: "%.0f", msg.measuredSNR) : "0.0")
                        .font(.caption2)
                        .foregroundStyle(!msg.measuredSNR.isNaN ? Color.secondary : Color.secondary.opacity(0))
                    
                    Text(!msg.frequency.isNaN ? String(format: "%.0f", msg.frequency) : "0.0")
                        .font(.caption2)
                        .foregroundStyle(!msg.frequency.isNaN ? Color.secondary : Color.secondary.opacity(0))
                    
                    Text(!msg.timeOffset.isNaN ? String(format: "%.2fs", msg.timeOffset) : "0.00")
                        .font(.caption2)
                        .foregroundStyle(
                            !msg.timeOffset.isNaN
                            ? (msg.timeOffset > 0.2 ? Color.red : .secondary)
                            : .secondary.opacity(0)
                        )
                }
                .frame(minWidth: 60, alignment: .trailing)
                
                HStack(alignment: .top, spacing: 4) {
                    if msg.isTX {
                        Text("TX")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    
                    Text(msg.text)
                        .font(.caption)
                        .foregroundStyle((msg.forMe && !msg.isTX) ? Color.blue.opacity(0.85) : .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("(\(msg.mode.rawValue.uppercased()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 5)
            .background(Color(UIColor.systemBackground).opacity(0.001))
        }
    }
}

#Preview("CondensedMsgView") {
    CondensedMsgView(msg: PreviewMocks.rxMessages[0])
    CondensedMsgView(msg: PreviewMocks.rxMessages[0])
    CondensedMsgView(msg: PreviewMocks.rxMessages[0])
    CondensedMsgView(msg: PreviewMocks.rxMessages[0])
}
