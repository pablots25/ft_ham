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
    @ObservedObject private var rowColors = RowColorStore.shared
    let messages: [FT8Message]
    let allowReply: Bool

    @AppStorage("replyTapGesture") private var replyTapGesture: ReplyTapGesture = .single

    @Binding var filterMode: Int

    private var filteredMessages: [FT8Message] {
        RXFilterMode(storage: filterMode).apply(messages, isNeeded: viewModel.isNeeded)
    }

    var body: some View {
        // Filter once per body pass (this used to be evaluated three times).
        let filtered = filteredMessages
        return VStack(spacing: 0) {
            // MARK: - Header

            MessageListHeaderView(
                allowReply: allowReply
            )

            Divider()
                .padding(.vertical, 2)

            ScrollViewReader { scrollProxy in
                List {
                    if filtered.isEmpty {
                        Text("No messages")
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("empty")
                    } else {
                        ForEach(filtered) { msg in
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
                                let highlight = viewModel.rowHighlight(for: msg)
                                MessageView(msg: msg, needed: viewModel.showNeededBadges ? viewModel.neededStatus(for: msg) : [], highlight: highlight)
                                    .font(.caption2)
                                    .dynamicTypeSize(.medium ... .accessibility5)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 0, alignment: .center)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: replyTapGesture.tapCount) {
                                        guard msg.allowsReply && allowReply else { return }
                                        Haptics.light()
                                        viewModel.reply(to: msg)
                                    }
                                    .accessibilityIdentifier("decodeRow_\(msg.callsign ?? "")")
                                    .swipeActionsIfNeeded(allowReply: msg.allowsReply && allowReply) {
                                        viewModel.reply(to: msg)
                                    }
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(backgroundColor(for: msg, isNewCallsign: viewModel.isNewCQCallsign(msg), highlight: highlight, colors: rowColors))
                                    .id(msg.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // Defer the scroll to the next runloop turn: scrolling synchronously
                // while SwiftUI is still applying the List diff makes UIKit target a
                // stale index and crash with NSInternalInconsistencyException
                // ("Attempted to scroll ... out-of-bounds item").
                .onChange(of: filtered.last?.id) { lastId in
                    guard let lastId else { return }
                    DispatchQueue.main.async {
                        withAnimation {
                            scrollProxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let lastId = filtered.last?.id {
                        DispatchQueue.main.async {
                            scrollProxy.scrollTo(lastId, anchor: .bottom)
                        }
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
