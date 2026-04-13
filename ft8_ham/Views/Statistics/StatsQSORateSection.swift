//
//  StatsQSORateSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsQSORateSection: View {
    let data: [(date: Date, rate: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("QSO Rate")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                rateChart

                if let avg = averageRate, let peak = peakRate {
                    HStack {
                        Label("Avg: \(String(format: "%.1f", avg))/hr", systemImage: "chart.line.flattrend.xyaxis")
                        Spacer()
                        Label("Peak: \(String(format: "%.0f", peak))/hr", systemImage: "bolt")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                }
            }
        }
    }

    private var rateChart: some View {
        Chart(Array(data.suffix(100).enumerated()), id: \.offset) { _, item in
            BarMark(
                x: .value("Time", item.date),
                y: .value("QSOs/hr", item.rate)
            )
            .foregroundStyle(Color.mint.gradient)
            .cornerRadius(2)
        }
        .frame(height: 160)
        .padding(.horizontal)
    }

    private var averageRate: Double? {
        guard !data.isEmpty else { return nil }
        return data.map(\.rate).reduce(0, +) / Double(data.count)
    }

    private var peakRate: Double? {
        data.map(\.rate).max()
    }

    private var noDataView: some View {
        Text("No rate data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
