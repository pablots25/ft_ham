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
    /// Tap-to-reply handler. Kept in this modifier (rather than a separate
    /// .onTapGesture at the call site) so the tap and the swipe drag share the
    /// same view level and coordinate space. Previously the call-site tap sat
    /// on the un-offset inner content while this modifier applied .offset and
    /// .clipped() around it, which shifted the tap's hit-test region on wider
    /// iPad layouts and let the drag recognizer swallow pointer/trackpad clicks.
    let onTap: () -> Void
    @Binding var dragOffset: [UUID: CGFloat]
    @Binding var didTriggerHaptic: [UUID: Bool]
    @Binding var userDragging: Bool

    private let triggerThreshold: CGFloat = -60
    private let maxDrag: CGFloat = -90         // clamp so the row doesn't slide too far
    private let dampingFactor: CGFloat = 0.4   // resistance past trigger threshold
    // Pointer/trackpad "clicks" on iPad carry small incidental movement. A larger
    // activation distance keeps those from being claimed as a drag (which would
    // swallow the tap); the onChanged handler additionally requires the motion to
    // be horizontal-dominant before it moves the row.
    private let dragActivation: CGFloat = 25

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // Reply indicator revealed behind the sliding row
            let offset = dragOffset[messageID] ?? 0
            if offset < -10 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 14)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .scaleEffect(x: min((abs(offset) - 10) / 50.0, 1.0), anchor: .trailing)
                    .opacity(min((abs(offset) - CGFloat(10)) / 40.0, 1.0))
                    .padding(.vertical, 1)
            }

            content
                .contentShape(Rectangle())
                .offset(x: dragOffset[messageID] ?? 0)
                .onTapGesture {
                    guard allowReply else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTap()
                }
                // simultaneousGesture lets the parent ScrollView still scroll vertically
                .simultaneousGesture(
                    DragGesture(minimumDistance: dragActivation)
                        .onChanged { value in
                            guard allowReply else { return }
                            // Ignore if movement is more vertical than horizontal
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            // Only left swipe
                            guard value.translation.width < 0 else { return }

                            // Apply damping past the trigger threshold for a rubber-band feel
                            let raw = value.translation.width
                            let damped = raw > triggerThreshold
                                ? raw
                                : triggerThreshold + (raw - triggerThreshold) * dampingFactor
                            dragOffset[messageID] = max(damped, maxDrag)
                            userDragging = true

                            if (dragOffset[messageID] ?? 0) <= triggerThreshold &&
                               didTriggerHaptic[messageID] != true {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                didTriggerHaptic[messageID] = true
                            }
                        }
                        .onEnded { _ in
                            if (dragOffset[messageID] ?? 0) <= triggerThreshold {
                                onReply()
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                dragOffset[messageID] = 0
                            }
                            didTriggerHaptic[messageID] = false
                            // Always reset — don't check animation state (values aren't 0 yet)
                            userDragging = false
                        }
                )
        }
        // Clip so the sliding row never bleeds outside its own bounds
        .clipped()
        .frame(maxWidth: .infinity)
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
        onTap: @escaping () -> Void,
        onReply: @escaping () -> Void
    ) -> some View {
        self.modifier(SwipeToReplyModifier(
            allowReply: allowReply,
            messageID: messageID,
            onReply: onReply,
            onTap: onTap,
            dragOffset: dragOffset,
            didTriggerHaptic: didTriggerHaptic,
            userDragging: userDragging
        ))
    }
}
