//
//  StatsStreaksSection.swift
//  ft_ham
//

import SwiftUI

struct StatsStreaksSection: View {
    let longestStreak: Int
    let currentStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Operating Streaks")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: LayoutConstants.compactSpacing) {
                StreakCard(
                    title: "Current",
                    days: currentStreak,
                    icon: "flame",
                    color: currentStreak > 0 ? .orange : .gray
                )
                StreakCard(
                    title: "Longest",
                    days: longestStreak,
                    icon: "trophy",
                    color: .yellow
                )
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - StreakCard

private struct StreakCard: View {
    let title: String
    let days: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text("\(days)")
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(days == 1 ? "Day" : "Days")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
