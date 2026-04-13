//
//  StatsSnrScatterSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsSnrScatterSection: View {
    let data: [(txSnr: Double, rxSnr: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("TX vs RX Signal")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { _, item in
                    PointMark(
                        x: .value("TX SNR", item.txSnr),
                        y: .value("RX SNR", item.rxSnr)
                    )
                    .foregroundStyle(Color.indigo.opacity(0.5))
                    .symbolSize(24)
                }
                .chartXAxisLabel("Sent (dB)")
                .chartYAxisLabel("Received (dB)")
                .frame(height: 200)
                .padding(.horizontal)
            }
        }
    }

    private var noDataView: some View {
        Text("No SNR data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
