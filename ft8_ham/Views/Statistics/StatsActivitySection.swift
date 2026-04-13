//
//  StatsActivitySection.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI
import Charts

struct StatsActivitySection: View {
    let series: [(date: Date, count: Int)]
    let isDaily: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Activity")
                .font(.headline)
                .padding(.horizontal)

            if series.isEmpty {
                noDataView
            } else {
                Chart(series, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: isDaily ? .day : .month),
                        y: .value("QSOs", item.count)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(2)
                }
                .chartYAxisLabel("QSOs")
                .chartXAxis {
                    if isDaily {
                        AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            AxisGridLine()
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            AxisGridLine()
                        }
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)
            }
        }
    }

    private var stride: Int {
        let count = series.count
        if count <= 14 { return 1 }
        if count <= 30 { return 2 }
        return 5
    }

    private var noDataView: some View {
        Text("No activity data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
