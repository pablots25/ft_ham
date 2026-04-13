//
//  StatsTopCallsignsSection.swift
//  ft_ham
//

import SwiftUI

struct StatsTopCallsignsSection: View {
    let data: [(callsign: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Most Contacted")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text("#\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                            Text(item.callsign)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .monospaced()
                            Spacer()
                            Text("\(item.count) QSOs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        if index < data.count - 1 {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
                .padding(.horizontal)
            }
        }
    }

    private var noDataView: some View {
        Text("No data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
