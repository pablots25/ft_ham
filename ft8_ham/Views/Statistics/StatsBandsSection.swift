//
//  StatsBandsSection.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI
import Charts

struct StatsBandsSection: View {
    let data: [(key: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Bands")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                Chart(data, id: \.key) { item in
                    BarMark(
                        x: .value("QSOs", item.count),
                        y: .value("Band", item.key)
                    )
                    .foregroundStyle(LogbookBadgeColors.band(item.key).gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                    }
                }
                .frame(height: CGFloat(max(data.count, 1)) * 36)
                .padding(.horizontal)
            }
        }
    }

    private var noDataView: some View {
        Text("No band data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
