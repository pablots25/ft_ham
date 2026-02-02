//
//  SwipeToReplyModifier.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/01/26.
//

import SwiftUI
import UIKit

// MARK: - SwipeToReplyModifier

struct SwipeToReplyModifier: ViewModifier {
    let allowReply: Bool
    let messageID: UUID
    let onReply: () -> Void
    @Binding var dragOffset: [UUID: CGFloat]
    @Binding var didTriggerHaptic: [UUID: Bool]
    @Binding var userDragging: Bool

    private let swipeZoneWidth: CGFloat = 36
    private let triggerThreshold: CGFloat = -60

    func body(content: Content) -> some View {
        ZStack {
            // Reply indicator background
            HStack {
                Spacer()
                if let offset = dragOffset[messageID], offset < -10 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .foregroundStyle(.white)
                            .frame(width: max(abs(offset) - 30, 20))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(20)
                    .opacity(min((abs(offset) - 10) / CGFloat(50), 1))
                    .animation(.easeOut(duration: 0.15), value: offset)
                }
            }

            content
                .offset(x: dragOffset[messageID] ?? 0)
                .overlay(
                    // Invisible swipe area
                    Group {
                        if allowReply {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: swipeZoneWidth)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { value in
                                            guard value.translation.width < 0 else { return }
                                            dragOffset[messageID] = value.translation.width
                                            userDragging = true

                                            if value.translation.width < triggerThreshold &&
                                                didTriggerHaptic[messageID] != true {
                                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                                generator.impactOccurred()
                                                didTriggerHaptic[messageID] = true
                                            }
                                        }
                                        .onEnded { value in
                                            if value.translation.width < triggerThreshold {
                                                onReply()
                                            }
                                            withAnimation(.spring()) {
                                                dragOffset[messageID] = 0
                                                didTriggerHaptic[messageID] = false
                                            }
                                            // Reactivate autoscroll inmediatamente
                                            if dragOffset.values.allSatisfy({ $0 == 0 }) {
                                                userDragging = false
                                            }
                                        }
                                )
                        }
                    },
                    alignment: .trailing
                )
        }
    }
}

// MARK: - View Extension

extension View {
    func swipeToReply(
        allowReply: Bool,
        messageID: UUID,
        dragOffset: Binding<[UUID: CGFloat]>,
        didTriggerHaptic: Binding<[UUID: Bool]>,
        userDragging: Binding<Bool>,
        onReply: @escaping () -> Void
    ) -> some View {
        self.modifier(SwipeToReplyModifier(
            allowReply: allowReply,
            messageID: messageID,
            onReply: onReply,
            dragOffset: dragOffset,
            didTriggerHaptic: didTriggerHaptic,
            userDragging: userDragging
        ))
    }
}
