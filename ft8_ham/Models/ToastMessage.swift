//
//  ToastMessage.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/3/26.
//

import SwiftUI

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
