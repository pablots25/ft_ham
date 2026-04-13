//
//  StatsModeSection.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI
import Charts

struct StatsModeSection: View {
    let data: [(key: String, count: Int)]

    private var total: Int { data.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Modes")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty || total == 0 {
                noDataView
            } else {
                chartContent
            }
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        if #available(iOS 17.0, *) {
            donutChart
        } else {
            barChart
        }
    }

    @available(iOS 17.0, *)
    private var donutChart: some View {
            Chart(data, id: \.key) { item in
            SectorMark(
                angle: .value("QSOs", item.count),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .foregroundStyle(LogbookBadgeColors.mode(item.key).gradient)
            .annotation(position: .overlay) {
                VStack(spacing: 2) {
                    Text(item.key)
                        .font(.caption.bold())
                    Text("\(item.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(height: 200)
        .padding(.horizontal)
        .overlay {
            VStack {
                Text("\(total)")
                    .font(.title2.bold())
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var barChart: some View {
        Chart(data, id: \.key) { item in
            BarMark(
                x: .value("QSOs", item.count),
                y: .value("Mode", item.key)
            )
            .foregroundStyle(LogbookBadgeColors.mode(item.key).gradient)
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                Text("\(item.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: CGFloat(max(data.count, 1)) * 40)
        .padding(.horizontal)
    }

    private var noDataView: some View {
        Text("No mode data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
