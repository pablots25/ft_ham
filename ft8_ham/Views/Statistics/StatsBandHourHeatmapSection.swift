//
//  StatsBandHourHeatmapSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsBandHourHeatmapSection: View {
    let data: [BandHourCell]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Band × Hour Heatmap")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                heatmapChart
            }
        }
    }

    private var heatmapChart: some View {
        let bands = Array(Set(data.map(\.band))).sorted { bandOrder($0) < bandOrder($1) }
        let maxCount = data.map(\.count).max() ?? 1

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                // Hour labels
                HStack(spacing: 2) {
                    Color.clear.frame(width: 36, height: 14)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour % 3 == 0 ? "\(hour)" : "")
                            .font(.system(size: 8))
                            .frame(width: 14, height: 14)
                    }
                }

                ForEach(bands, id: \.self) { band in
                    HStack(spacing: 2) {
                        Text(band)
                            .font(.caption2)
                            .frame(width: 36, alignment: .trailing)
                        ForEach(0..<24, id: \.self) { hour in
                            let count = cellCount(band: band, hour: hour)
                            let intensity = maxCount > 0 ? Double(count) / Double(maxCount) : 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cellColor(intensity: intensity))
                                .frame(width: 14, height: 14)
                                .overlay {
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                    }
                }

                // Legend
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(intensity: intensity))
                            .frame(width: 12, height: 12)
                    }
                    Text("More")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)
        }
    }

    private func cellCount(band: String, hour: Int) -> Int {
        data.first { $0.band == band && $0.hour == hour }?.count ?? 0
    }

    private func cellColor(intensity: Double) -> Color {
        if intensity <= 0 { return Color(.systemGray5) }
        return Color.blue.opacity(0.2 + intensity * 0.8)
    }

    private func bandOrder(_ band: String) -> Int {
        let order = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
        return order.firstIndex(of: band) ?? 99
    }

    private var noDataView: some View {
        Text("No data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
