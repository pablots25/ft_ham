//
//  StatsRecordsSection.swift
//  ft_ham
//

import SwiftUI

struct StatsRecordsSection: View {
    let records: StatsRecords

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Records & Milestones")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: LayoutConstants.compactSpacing) {
                if let busiest = records.busiestDay {
                    RecordRow(
                        icon: "calendar.badge.exclamationmark",
                        title: "Busiest Day",
                        value: "\(busiest.count) QSOs",
                        detail: busiest.date.formatted(.dateTime.day().month(.abbreviated).year()),
                        color: .orange
                    )
                }

                if let busiestHour = records.busiestHour {
                    RecordRow(
                        icon: "clock.badge.exclamationmark",
                        title: "Busiest Hour",
                        value: "\(busiestHour.count) QSOs",
                        detail: busiestHour.date.formatted(.dateTime.day().month(.abbreviated).hour()),
                        color: .red
                    )
                }
            }
            .padding(.horizontal)

            if !records.firstQSOPerBand.isEmpty {
                firstQSOPerBandView
            }
        }
    }

    private var firstQSOPerBandView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("First QSO per Band")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)

            VStack(spacing: 0) {
                let sorted = records.firstQSOPerBand.sorted {
                    bandOrder($0.band) < bandOrder($1.band)
                }
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item.band)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(LogbookBadgeColors.band(item.band))
                            .frame(width: 40, alignment: .leading)
                        Text(item.callsign)
                            .font(.subheadline)
                            .monospaced()
                        Spacer()
                        Text(item.date.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                    if index < sorted.count - 1 {
                        Divider().padding(.leading)
                    }
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
            .padding(.horizontal)
        }
    }

    private func bandOrder(_ band: String) -> Int {
        let order = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
        return order.firstIndex(of: band) ?? 99
    }
}

// MARK: - RecordRow

private struct RecordRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .padding(LayoutConstants.compactPadding)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
    }
}
