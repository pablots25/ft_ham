//
//  StatsGrowthCurvesSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsGrowthCurvesSection: View {
    let countriesOverTime: [(date: Date, cumulative: Int)]
    let gridsOverTime: [(date: Date, cumulative: Int)]
    let callsignsOverTime: [(date: Date, cumulative: Int)]

    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Growth Over Time")
                .font(.headline)
                .padding(.horizontal)

            Picker("Growth Type", selection: $selectedTab) {
                Text("Countries").tag(0)
                Text("Grids").tag(1)
                Text("Callsigns").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch selectedTab {
            case 0: growthChart(data: countriesOverTime, label: "Countries", color: .green)
            case 1: growthChart(data: gridsOverTime, label: "Grids", color: .orange)
            default: growthChart(data: callsignsOverTime, label: "Callsigns", color: .blue)
            }
        }
    }

    private func growthChart(data: [(date: Date, cumulative: Int)], label: String, color: Color) -> some View {
        Group {
            if data.isEmpty {
                Text("No data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(data, id: \.date) { item in
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value(label, item.cumulative)
                    )
                    .foregroundStyle(color.gradient)
                    .interpolationMethod(.stepEnd)

                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value(label, item.cumulative)
                    )
                    .foregroundStyle(color.opacity(0.1).gradient)
                    .interpolationMethod(.stepEnd)
                }
                .frame(height: 180)
                .padding(.horizontal)
            }
        }
    }
}
