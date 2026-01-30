//
//  MessageListView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI

// MARK: - MessageListView

struct MessageListView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    let messages: [FT8Message]
    let allowReply: Bool

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header

            HStack(alignment: .center, spacing: 20) {
                Text("Time")
                Text("dB")
                    .opacity(allowReply ? 1.0 : 0.0)
                Text("Freq.")
                Text("Δt")
                    .opacity(allowReply ? 1.0 : 0.0)
            }
            .padding(.horizontal, 4)
            .font(.caption2)
            .dynamicTypeSize(.medium ... .accessibility5)
            .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 2)

            ScrollViewReader { scrollProxy in
                List {
                    if messages.isEmpty {
                        Text("No messages")
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .id("empty")
                    } else {
                        ForEach(messages) { msg in
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
                // Scroll to last message whenever messages append
                .onChange(of: messages.last?.id) { _, lastId in
                    guard let lastId else { return }
                    withAnimation {
                        scrollProxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                // Scroll to last message on appear
                .onAppear {
                    if let lastId = messages.last?.id {
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
