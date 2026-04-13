//
//  StatsTimeOfDaySection.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI
import Charts

struct StatsTimeOfDaySection: View {
    let data: [(hour: Int, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Time of Day (UTC)")
                .font(.headline)
                .padding(.horizontal)

            if data.allSatisfy({ $0.count == 0 }) {
                noDataView
            } else {
                Chart(data, id: \.hour) { item in
                    BarMark(
                        x: .value("Hour", "\(String(format: "%02d", item.hour))"),
                        y: .value("QSOs", item.count)
                    )
                    .foregroundStyle(hourColor(item.hour).gradient)
                    .cornerRadius(2)
                }
                .chartYAxisLabel("QSOs")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8))
                }
                .frame(height: 180)
                .padding(.horizontal)
            }
        }
    }

    private func hourColor(_ hour: Int) -> Color {
        switch hour {
        case 6..<12:  return .orange    // Morning
        case 12..<18: return .yellow    // Afternoon
        case 18..<22: return .indigo    // Evening
        default:      return .blue      // Night
        }
    }

    private var noDataView: some View {
        Text("No time data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
