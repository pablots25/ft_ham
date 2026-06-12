//
//  StatisticsViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/04/26.
//

import SwiftUI

/// Stub Statistics view — shown only when premium package is not linked.
public struct StatisticsViewStub: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Statistics")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Premium Feature")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Detailed QSO statistics, band activity heatmaps and charts require a premium subscription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
        }
        .padding()
    }
}
