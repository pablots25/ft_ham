//
//  StatsSignalSection.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI
import Charts

struct StatsSignalSection: View {
    let buckets: [(label: String, count: Int)]
    let avgSnr: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            HStack {
                Text("Signal Strength (SNR)")
                    .font(.headline)
                Spacer()
                if let avg = avgSnr {
                    Text(String(format: "Avg: %+.1f dB", avg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if buckets.allSatisfy({ $0.count == 0 }) {
                noDataView
            } else {
                Chart(buckets, id: \.label) { item in
                    BarMark(
                        x: .value("SNR", item.label),
                        y: .value("QSOs", item.count)
                    )
                    .foregroundStyle(snrColor(for: item.label).gradient)
                    .cornerRadius(4)
                }
                .chartYAxisLabel("QSOs")
                .frame(height: 180)
                .padding(.horizontal)
            }
        }
    }

    private func snrColor(for label: String) -> Color {
        if label.hasPrefix(">") || label.hasPrefix("+6") { return .green }
        if label.hasPrefix("0") { return .yellow }
        if label.hasPrefix("-6") { return .orange }
        return .red
    }

    private var noDataView: some View {
        Text("No signal data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
