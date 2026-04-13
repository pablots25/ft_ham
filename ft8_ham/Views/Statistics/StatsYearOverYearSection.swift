//
//  StatsYearOverYearSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsYearOverYearSection: View {
    let data: [YearMonthCount]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Year-over-Year")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        let years = Array(Set(data.map(\.year))).sorted()
        let monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

        return Chart {
            ForEach(years, id: \.self) { year in
                let yearData = data.filter { $0.year == year }
                ForEach(yearData) { item in
                    LineMark(
                        x: .value("Month", monthLabels[item.month - 1]),
                        y: .value("QSOs", item.count),
                        series: .value("Year", String(year))
                    )
                    .foregroundStyle(by: .value("Year", String(year)))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Month", monthLabels[item.month - 1]),
                        y: .value("QSOs", item.count)
                    )
                    .foregroundStyle(by: .value("Year", String(year)))
                    .symbolSize(20)
                }
            }
        }
        .chartLegend(position: .bottom)
        .frame(height: 200)
        .padding(.horizontal)
    }

    private var noDataView: some View {
        Text("No data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
