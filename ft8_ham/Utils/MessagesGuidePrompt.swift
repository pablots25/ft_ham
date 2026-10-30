//
//  MessagesGuidePrompt.swift
//  ft_ham
//

import Foundation

/// Opens the Messages Guide by itself the first time the TX/RX tab is shown,
/// so new operators learn the row colors, badges and quick reply.
enum MessagesGuidePrompt {
    static let seenKey = "hasSeenMessagesGuide"
    /// Lets a full-screen cover (onboarding, terms, What's New) finish
    /// dismissing before the guide's sheet is presented.
    static let presentationDelay: Duration = .milliseconds(600)

    /// - Parameters:
    ///   - tab: The tab on screen.
    ///   - hasSeen: Whether the guide was already shown once.
    ///   - isBlocked: Whether something else is on screen or still has to be,
    ///     such as onboarding, the terms, What's New or the settings alert.
    static func shouldPresent(tab: AppTab?, hasSeen: Bool, isBlocked: Bool) -> Bool {
        tab == .transmissions && !hasSeen && !isBlocked
    }
}
