//
//  MessageColorLegendView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 5/4/26.
//

import SwiftUI

/// Help sheet explaining message colors, the filter button, and swipe-to-reply.
struct MessageColorLegendView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Colors
                Section {
                    legendRow(fill: .yellow.opacity(0.2), stroke: .yellow,
                              label: "Your own CQ transmissions")
                    legendRow(fill: .purple.opacity(0.2), stroke: .purple,
                              label: "Received CQ from another station")
                    legendRow(fill: .blue.opacity(0.2), stroke: .blue,
                              label: "Message directed to you (grid exchange)")
                    legendRow(fill: .orange.opacity(0.2), stroke: .orange,
                              label: "Message directed to you (signal report)")
                    legendRow(fill: .purple.opacity(0.2), stroke: .purple,
                              label: "Final exchange \u{2014} RR73 / RRR / 73")
                    legendRow(fill: .gray.opacity(0.2), stroke: .gray,
                              label: "Unknown message type")
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                Color.secondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1, dash: [4])
                            )
                            .frame(width: 28, height: 16)
                        Text("Station-to-station (not involving you)")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Message Colors")
                }

                // MARK: - Filter
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show all messages")
                                .font(.subheadline)
                            Text("Every decoded message is shown, regardless of whether it involves your callsign.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 14) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My messages only")
                                .font(.subheadline)
                            Text("Only messages directly involving your callsign and your own transmissions are shown. CQ calls from others are hidden.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 14) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My messages + CQ calls")
                                .font(.subheadline)
                            Text("Shows messages involving you, your own transmissions, and all CQ calls — useful for monitoring new contacts while keeping noise down.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Tap the filter icon to cycle through the three modes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } header: {
                    Text("Filter Button")
                }

                // MARK: - Reply
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Image(systemName: "chevron.right.2")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Swipe right to reply")
                                .font(.subheadline)
                            Text("On any received message, swipe right to pre-fill it as your current QSO target. A short vibration confirms the selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Quick Reply")
                }

            }
            .listStyle(.plain)
            .navigationTitle("Messages Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func legendRow(fill: Color, stroke: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(stroke.opacity(0.7), lineWidth: 1.5)
                )
                .frame(width: 28, height: 16)
            Text(label)
                .font(.subheadline)
        }
    }
}

#Preview {
    MessageColorLegendView()
}
