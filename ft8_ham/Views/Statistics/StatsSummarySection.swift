//
//  StatsSummarySection.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI

struct StatsSummarySection: View {
    let summary: StatisticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Overview")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: LayoutConstants.compactSpacing),
                GridItem(.flexible(), spacing: LayoutConstants.compactSpacing)
            ], spacing: LayoutConstants.compactSpacing) {
                StatCard(
                    title: String(localized: "QSOs"),
                    value: "\(summary.totalQSOs)",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .blue
                )
                StatCard(
                    title: String(localized: "Countries"),
                    value: "\(summary.uniqueCountries)",
                    icon: "globe",
                    color: .green
                )
                StatCard(
                    title: String(localized: "Grids"),
                    value: "\(summary.uniqueGrids)",
                    icon: "square.grid.3x3",
                    color: .orange
                )
                StatCard(
                    title: String(localized: "Bands"),
                    value: "\(summary.uniqueBands)",
                    icon: "waveform",
                    color: .purple
                )
            }

            if let first = summary.firstQSO, let latest = summary.latestQSO {
                HStack {
                    Text("\(first, format: .dateTime.day().month(.abbreviated).year())")
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(latest, format: .dateTime.day().month(.abbreviated).year())")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LayoutConstants.standardPadding)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
    }
}
