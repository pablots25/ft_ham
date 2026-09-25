//
//  Haptics.swift
//  ft_ham
//
//  Created by Pablo Turrion on 25/09/26.
//

import UIKit

/// Plays haptic feedback through generators that stay alive between uses.
///
/// A feedback generator created inline and released right after firing is
/// never prepared, so the Taptic Engine is often still asleep and the first
/// tap after a pause produces nothing. These generators are retained and
/// prepared again after every use, which keeps the next one responsive.
@MainActor
enum Haptics {

    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionChange = UISelectionFeedbackGenerator()

    /// Warms up every generator. Call when a screen that uses haptics appears.
    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        notification.prepare()
        selectionChange.prepare()
    }

    /// A light tap, for small confirmations such as picking a row.
    static func light() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    /// A firmer tap, for committing an action such as a swipe reply.
    static func medium() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    /// A task finished successfully.
    static func success() {
        notify(.success)
    }

    /// Something needs the operator's attention.
    static func warning() {
        notify(.warning)
    }

    /// A task failed.
    static func error() {
        notify(.error)
    }

    /// A value in a picker or list changed.
    static func selection() {
        selectionChange.selectionChanged()
        selectionChange.prepare()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
        notification.prepare()
    }
}
