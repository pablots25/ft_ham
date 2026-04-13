//
//  StatsGridHeatmapSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsGridHeatmapSection: View {
    let data: [(field: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Grid Fields")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                fieldGrid
            }
        }
    }

    private var fieldGrid: some View {
        let maxCount = data.map(\.count).max() ?? 1
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

        return VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(data, id: \.field) { item in
                    let intensity = Double(item.count) / Double(maxCount)
                    VStack(spacing: 2) {
                        Text(item.field)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("\(item.count)")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15 + intensity * 0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal)

            Text("\(data.count) grid fields worked")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private var noDataView: some View {
        Text("No grid data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
