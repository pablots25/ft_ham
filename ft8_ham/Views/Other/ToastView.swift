//
//  ToastView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/3/26.
//

import SwiftUI

// MARK: - Toast Overlay Modifier

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?
    @State private var workItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    toastView(toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(999)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
            .onChange(of: toast) { newValue in
                if let newValue {
                    scheduleAutoDismiss(after: newValue.duration)
                }
            }
    }

    private func toastView(_ toast: ToastMessage) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white)
                Image(systemName: toast.systemImage)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(toast.color)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            Text(toast.message)
                .font(.system(.subheadline, design: .default).weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .onTapGesture { dismissToast() }
    }

    private func scheduleAutoDismiss(after duration: TimeInterval) {
        workItem?.cancel()
        let item = DispatchWorkItem { dismissToast() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func dismissToast() {
        withAnimation { toast = nil }
        workItem?.cancel()
        workItem = nil
    }
}

// MARK: - View Extension

extension View {
    func toast(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
