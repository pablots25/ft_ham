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
    @AppStorage("showCountryFlags") private var showCountryFlags: Bool = true
    @AppStorage("showCountryNames") private var showCountryNames: Bool = false

    private var callsignCountryLine: String? {
        var parts: [String] = []

        if let call = msg.callsign,
           !call.isEmpty,
           let country = msg.senderCountry.country,
           !country.isEmpty {
            parts.append("\(call): \(country)")
        }

        if let dx = msg.dxCallsign,
           !dx.isEmpty,
           dx != msg.callsign,
           let country = msg.dxCountry.country,
           !country.isEmpty {
            parts.append("\(dx): \(country)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
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
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 4) {
                        if msg.isTX {
                            Text("TX")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        
                        Text(showCountryFlags ? FlagUtility.addFlags(to: msg) : msg.text)
                            .font(.caption)
                            .foregroundStyle((msg.forMe && !msg.isTX) ? Color.blue.opacity(0.85) : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("(\(msg.mode.rawValue.uppercased()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if showCountryNames, let line = callsignCountryLine {
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
