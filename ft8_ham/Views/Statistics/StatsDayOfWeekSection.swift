//
//  StatsDayOfWeekSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsDayOfWeekSection: View {
    let data: [(day: Int, label: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Day of Week")
                .font(.headline)
                .padding(.horizontal)

            if data.allSatisfy({ $0.count == 0 }) {
                noDataView
            } else {
                Chart(data, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.label),
                        y: .value("QSOs", item.count)
                    )
                    .foregroundStyle(Color.cyan.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
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
