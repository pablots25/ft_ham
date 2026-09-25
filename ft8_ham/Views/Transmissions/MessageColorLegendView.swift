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
    @ObservedObject private var rowColors = RowColorStore.shared

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Colors
                Section {
                    ForEach(MessageRowColor.allCases) { kind in
                        legendRow(fill: rowColors.tint(kind), stroke: rowColors.color(kind), label: kind.label)
                    }
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
                } footer: {
                    Text("You can change these colors in Settings, under Display.")
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
                    HStack(spacing: 14) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.teal)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Needed only")
                                .font(.subheadline)
                            Text("Shows only stations that would add something to your log on the current band and mode: a new callsign, grid or DXCC. Your own transmissions stay visible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Tap the filter icon to cycle through the four modes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } header: {
                    Text("Filter Button")
                }

                // MARK: - Badges
                Section {
                    HStack(spacing: 14) {
                        NeededBadgeView(status: [.grid])
                            .frame(width: 60, alignment: .leading)
                        Text("Grid square not yet in your log on this band and mode")
                            .font(.subheadline)
                    }
                    HStack(spacing: 14) {
                        NeededBadgeView(status: [.dxcc])
                            .frame(width: 60, alignment: .leading)
                        Text("Country (DXCC) not yet in your log on this band and mode")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Badges")
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
