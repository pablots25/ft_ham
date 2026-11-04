//
//  ToastMessage.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/3/26.
//

import SwiftUI

struct ToastMessage: Equatable {
    let message: String
    /// SF Symbol glyph drawn inside the white circular badge (use non-circled glyphs).
    let systemImage: String
    /// Tint of the glyph inside the badge.
    let color: Color
    let duration: TimeInterval

    /// How long every toast stays on screen.
    static let defaultDuration: TimeInterval = 5

    static func success(_ message: String, duration: TimeInterval = defaultDuration) -> ToastMessage {
        ToastMessage(message: message, systemImage: "checkmark", color: .black, duration: duration)
    }

    static func warning(_ message: String, duration: TimeInterval = defaultDuration) -> ToastMessage {
        ToastMessage(message: message, systemImage: "exclamationmark", color: .orange, duration: duration)
    }

    static func info(_ message: String, duration: TimeInterval = defaultDuration) -> ToastMessage {
        ToastMessage(message: message, systemImage: "info", color: .blue, duration: duration)
    }
}
