//
//  StatsContinentSection.swift
//  ft_ham
//

import SwiftUI
import Charts

struct StatsContinentSection: View {
    let data: [(continent: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text("Continents")
                .font(.headline)
                .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                Chart(data, id: \.continent) { item in
                    BarMark(
                        x: .value("QSOs", item.count),
                        y: .value("Continent", continentLabel(item.continent))
                    )
                    .foregroundStyle(continentColor(item.continent).gradient)
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

    private func continentColor(_ continent: String) -> Color {
        switch continent {
        case "NA": return .blue
        case "SA": return .green
        case "EU": return .purple
        case "AF": return .orange
        case "AS": return .red
        case "OC": return .cyan
        default: return .gray
        }
    }

    private func continentLabel(_ code: String) -> String {
        switch code {
        case "NA": return "North America"
        case "SA": return "South America"
        case "EU": return "Europe"
        case "AF": return "Africa"
        case "AS": return "Asia"
        case "OC": return "Oceania"
        default: return "Unknown"
        }
    }

    private var noDataView: some View {
        Text("No data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
