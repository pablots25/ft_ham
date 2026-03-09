//
//  ToastView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/3/26.
//

import SwiftUI

// MARK: - Toast Model

struct ToastMessage: Equatable {
    let message: String
    let systemImage: String
    let color: Color
    let duration: TimeInterval

    static func warning(_ message: String, duration: TimeInterval = 4) -> ToastMessage {
        ToastMessage(message: message, systemImage: "exclamationmark.triangle.fill", color: .orange, duration: duration)
    }

    static func info(_ message: String, duration: TimeInterval = 3) -> ToastMessage {
        ToastMessage(message: message, systemImage: "info.circle.fill", color: .blue, duration: duration)
    }
}

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
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(toast.color)
                .font(.system(size: 16, weight: .semibold))

            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(toast.color.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
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
