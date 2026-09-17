//
//  CondensedMsgListView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - CondensedMsgListView

struct CondensedMsgListView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    let messages: [FT8Message]
    let allowReply: Bool

    @State private var dragOffset: [UUID: CGFloat] = [:]
    @State private var didTriggerHaptic: [UUID: Bool] = [:]
    @State private var userDragging: Bool = false

    @Binding var filterMode: Int

    private var filteredMessages: [FT8Message] {
        RXFilterMode(storage: filterMode).apply(messages, isNeeded: viewModel.isNeeded)
    }

    var body: some View {
        // Filter once per body pass (this used to be evaluated three times).
        let filtered = filteredMessages
        return VStack(alignment: .leading, spacing: 0) {
            MessageListHeaderView(
                allowReply: allowReply
            )

            Divider()
                .padding(.vertical, 2)

            // MARK: - Messages
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: only the visible rows are built. The list is bounded
                    // but still holds up to a couple of thousand rows.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if filtered.isEmpty {
                            Text("No messages")
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                                .id("empty")
                        } else {
                            ForEach(filtered) { msg in
                                if msg.msgType == .internalTimestamp {
                                    CondensedMsgView(msg: msg)
                                        .font(.caption2)
                                        .dynamicTypeSize(.medium ... .accessibility5)
                                        .foregroundStyle(.secondary)
                                        .underline()
                                        .lineLimit(1)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 2)
                                        .id(msg.id)
                                } else {
                                    CondensedMsgView(msg: msg, needed: viewModel.showNeededBadges ? viewModel.neededStatus(for: msg) : [])
                                        .font(.body)
                                        .dynamicTypeSize(.medium ... .accessibility5)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                        .background(backgroundColor(for: msg, isNewCallsign: viewModel.isNewCQCallsign(msg)))
                                        .swipeToReply(
                                            allowReply: allowReply && msg.allowsReply,
                                            messageID: msg.id,
                                            dragOffset: $dragOffset,
                                            didTriggerHaptic: $didTriggerHaptic,
                                            userDragging: $userDragging,
                                            onTap: { viewModel.reply(to: msg) }
                                        ) {
                                            viewModel.reply(to: msg)
                                        }
                                        .accessibilityIdentifier("decodeRow_\(msg.callsign ?? "")")
                                        .id(msg.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                // Scroll to last message when a new one is appended
                .onChange(of: filtered.last?.id) { lastID in
                    guard let lastID else { return }
                    guard !userDragging else { return }

                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                // Scroll to last message on appear
                .onAppear {
                    if let lastID = filtered.last?.id {
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}
