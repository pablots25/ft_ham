//
//  SeparatedMsgListView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import SwiftUI
import UIKit

// MARK: - SeparatedMsgListView

struct SeparatedMsgListView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    let messages: [FT8Message]
    let allowReply: Bool

    @State private var dragOffset: [UUID: CGFloat] = [:]
    @State private var didTriggerHaptic: [UUID: Bool] = [:]
    @State private var userDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            HStack(spacing: 25) {
                Text("Time")
                Text("dB")
                    .opacity(allowReply ? 1.0 : 0.0)
                Text("Freq.")
                Text("Δt")
                    .opacity(allowReply ? 1.0 : 0.0)
            }
            .font(.caption)
            .dynamicTypeSize(.medium ... .accessibility5)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            Divider()
                .padding(.vertical, 2)

            // MARK: - Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if messages.isEmpty {
                            Text("No messages")
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                                .id("empty")
                        } else {
                            ForEach(messages) { msg in
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
                                    CondensedMsgView(msg: msg)
                                        .font(.body)
                                        .dynamicTypeSize(.medium ... .accessibility5)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                        .background(backgroundColor(for: msg))
                                        .swipeToReply(
                                            allowReply: allowReply && msg.allowsReply,
                                            messageID: msg.id,
                                            dragOffset: $dragOffset,
                                            didTriggerHaptic: $didTriggerHaptic,
                                            userDragging: $userDragging
                                        ) {
                                            viewModel.reply(to: msg)
                                        }
                                        .id(msg.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                // Scroll to last message whenever a new one is appended
                .onChange(of: messages.last?.id) { _, lastID in
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
                    if let lastID = messages.last?.id {
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
