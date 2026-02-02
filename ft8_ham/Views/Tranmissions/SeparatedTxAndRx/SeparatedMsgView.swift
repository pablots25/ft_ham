//
//  SeparatedMsgView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//


import SwiftUI

struct SeparatedMsgView: View {
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
            .padding(.horizontal, 10)
        } else {
            HStack(alignment: .top, spacing: 5) {
                HStack(spacing: 10) {
                    Text(DateFormatter.utcFormatterClock.string(from: msg.timestamp))
                        .foregroundStyle(.secondary)
                    Text(!msg.measuredSNR.isNaN ? String(format: "%.0f", msg.measuredSNR) : "0.0")
                        .foregroundStyle(!msg.measuredSNR.isNaN ? .secondary : Color.clear)
                    Text(!msg.frequency.isNaN ? String(format: "%.0f", msg.frequency) : "0.0")
                        .foregroundStyle(!msg.frequency.isNaN ? .secondary : Color.clear)
                    Text(!msg.timeOffset.isNaN ? String(format: "%.2fs", msg.timeOffset) : "0.00")
                        .foregroundStyle(
                            !msg.timeOffset.isNaN
                            ? (msg.timeOffset > 0.2 ? .red : .secondary)
                            : Color.clear
                        )
                }
                .font(.caption)

                HStack(alignment: .top, spacing: 5) {
                    if msg.isTX {
                        Text("TX")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    Text(msg.text)
                        .font(.subheadline)
                        .foregroundStyle((msg.forMe && !msg.isTX) ? Color.blue : Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("(\(msg.mode.rawValue.uppercased()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
        }
    }
}
