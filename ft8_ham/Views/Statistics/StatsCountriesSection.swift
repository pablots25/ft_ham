//
//  StatsCountriesSection.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI

struct StatsCountriesSection: View {
    let data: [(country: String, flag: String, count: Int)]

    @State private var showAll = false

    private var visibleData: [(country: String, flag: String, count: Int)] {
        showAll ? data : Array(data.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            HStack {
                Text("Countries")
                    .font(.headline)
                Spacer()
                Text("\(data.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if data.isEmpty {
                noDataView
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleData.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)

                            Text(item.flag)
                                .font(.title3)

                            Text(item.country)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Text("\(item.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)

                        if index < visibleData.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius))
                .padding(.horizontal)

                if data.count > 10 {
                    Button {
                        withAnimation { showAll.toggle() }
                    } label: {
                        Text(showAll ? "Show Less" : "Show All \(data.count) Countries")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var noDataView: some View {
        Text("No country data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
