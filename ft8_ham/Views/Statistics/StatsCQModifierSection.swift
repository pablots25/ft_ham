//
//  StatsCQModifierSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsCQModifierSection: View {
    let data: [(key: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("CQ Modifiers")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                Chart(data, id: \.key) { item in
                    BarMark(
                        x: .value("QSOs", item.count),
                        y: .value("Modifier", item.key)
                    )
                    .foregroundStyle(Color.teal.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: CGFloat(max(data.count, 1)) * 36)
                .padding(.horizontal)
            }
        }
    }

    private var noDataView: some View {
        Text("No CQ modifier data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
