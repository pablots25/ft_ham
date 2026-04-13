//
//  StatsDistanceSection.swift
//  ft_ham
//

import SwiftUI

struct StatsDistanceSection: View {
    let distanceStats: DistanceStats?
    let bestDX: [(callsign: String, country: String?, grid: String, distanceKm: Double)]
    let distanceByBand: [(band: String, avgKm: Double, maxKm: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Distance")
                .font(.headline)
                .padding(.horizontal)

            if let stats = distanceStats {
                distanceSummaryCards(stats)
            } else {
                Text("Set your grid locator to see distance statistics.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            if !bestDX.isEmpty {
                bestDXList
            }

            if !distanceByBand.isEmpty {
                distanceByBandList
            }
        }
    }

    private func distanceSummaryCards(_ stats: DistanceStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: LayoutConstants.compactSpacing),
            GridItem(.flexible(), spacing: LayoutConstants.compactSpacing)
        ], spacing: LayoutConstants.compactSpacing) {
            DistanceCard(title: "Best DX", value: formatKm(stats.maxKm), icon: "arrow.up.right", color: .red)
            DistanceCard(title: "Average", value: formatKm(stats.avgKm), icon: "chart.line.flattrend.xyaxis", color: .blue)
            DistanceCard(title: "Shortest", value: formatKm(stats.minKm), icon: "arrow.down.right", color: .green)
            DistanceCard(title: "Total", value: formatKm(stats.totalKm), icon: "globe", color: .purple)
        }
        .padding(.horizontal)
    }

    private var bestDXList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top DX Contacts")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(bestDX.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Text(item.callsign)
                            .font(.subheadline)
                            .monospaced()
                        if let country = item.country {
                            Text(country)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(formatKm(item.distanceKm))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                    if index < bestDX.count - 1 {
                        Divider().padding(.leading)
                    }
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
            .padding(.horizontal)
        }
    }

    private var distanceByBandList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Distance by Band")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(distanceByBand.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item.band)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(LogbookBadgeColors.band(item.band))
                            .frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Avg: \(formatKm(item.avgKm))")
                                .font(.caption)
                            Text("Max: \(formatKm(item.maxKm))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                    if index < distanceByBand.count - 1 {
                        Divider().padding(.leading)
                    }
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
            .padding(.horizontal)
        }
    }

    private func formatKm(_ km: Double) -> String {
        if km >= 1000 {
            return String(format: "%.0f km", km)
        }
        return String(format: "%.1f km", km)
    }
}

// MARK: - DistanceCard

private struct DistanceCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LayoutConstants.compactPadding)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
    }
}
