//
//  MessageListView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - MessageListView

struct MessageListView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    let messages: [FT8Message]
    let allowReply: Bool

    @Binding var showOnlyInvolved: Bool

    private var filteredMessages: [FT8Message] {
        guard showOnlyInvolved else { return messages }
        return messages.filter { $0.forMe || $0.isTX }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header

            MessageListHeaderView(
                allowReply: allowReply,
                showOnlyInvolved: $showOnlyInvolved
            )

            Divider()
                .padding(.vertical, 2)

            ScrollViewReader { scrollProxy in
                List {
                    if filteredMessages.isEmpty {
                        Text("No messages")
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("empty")
                    } else {
                        ForEach(filteredMessages) { msg in
                            if msg.msgType == .internalTimestamp {
                                MessageView(msg: msg)
                                    .font(.caption2)
                                    .dynamicTypeSize(.medium ... .accessibility5)
                                    .foregroundStyle(.primary)
                                    .underline()
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(maxWidth: .infinity, minHeight: 0, alignment: .center)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .id(msg.id)
                            } else {
                                MessageView(msg: msg)
                                    .font(.caption2)
                                    .dynamicTypeSize(.medium ... .accessibility5)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 0, alignment: .center)
                                    .contentShape(Rectangle())
                                    .swipeActionsIfNeeded(allowReply: msg.allowsReply && allowReply) {
                                        viewModel.reply(to: msg)
                                    }
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(backgroundColor(for: msg))
                                    .id(msg.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: filteredMessages.last?.id) { lastId in
                    guard let lastId else { return }
                    withAnimation {
                        scrollProxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let lastId = filteredMessages.last?.id {
                        scrollProxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Conditional Swipe Modifier

private extension View {
    @ViewBuilder
    func swipeActionsIfNeeded(allowReply: Bool, action: @escaping () -> Void) -> some View {
        if allowReply {
            swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(action: action) {
                    Label("", systemImage: "arrowshape.turn.up.left")
                }
                .tint(.green)
            }
        } else {
            self
        }
    }
}
