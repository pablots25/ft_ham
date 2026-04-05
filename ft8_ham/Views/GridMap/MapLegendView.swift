//
//  MapLegendView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 5/4/26.
//

import SwiftUI

/// Sheet explaining the overlay icons and colors shown on the grid map.
struct MapLegendView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                mapRow(label: "A locator you have already worked") {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.red, lineWidth: 1.5)
                        )
                        .frame(width: 28, height: 16)
                }
                mapRow(label: "A country you've heard in the last RX loop") {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .overlay(
                            Circle()
                                .stroke(Color.green, lineWidth: 1.5)
                        )
                        .frame(width: 18, height: 18)
                }
                mapRow(label: "Path between 2 stations contacting each other in the last RX loop") {
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: 28, height: 3)
                }
                mapRow(label: "Grid locator with callsign annotation") {
                    Image(systemName: "mappin")
                        .foregroundStyle(Color.blue)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                mapRow(label: "Your current location") {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Map Legend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func mapRow<Icon: View>(label: LocalizedStringKey, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 28, alignment: .center)
            Text(label)
                .font(.subheadline)
        }
    }
}

#Preview {
    MapLegendView()
}
