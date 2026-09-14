//
//  PremiumLockedRow.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import SwiftUI

/// A reusable row that shows a premium feature with a lock icon.
/// Tapping triggers the provided action (typically showing the paywall).
struct PremiumLockedRow: View {
    let feature: PremiumFeature
    let title: String
    let systemImage: String
    let action: () -> Void

    /// `title` and `systemImage` default to the feature's own name and icon;
    /// pass them explicitly when the row groups several features under one
    /// screen (e.g. "Reporting" gated by `.pskReporter`).
    init(
        feature: PremiumFeature,
        title: String? = nil,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.feature = feature
        self.title = title ?? feature.displayName
        self.systemImage = systemImage ?? feature.icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("premiumLocked_\(feature.rawValue)")
    }
}

/// Dims and disables inline content for non-premium users, overlaying a
/// transparent button that opens the paywall. Used where a premium block is
/// embedded in a scrolling page rather than reached through its own row.
struct PremiumLockedContent: ViewModifier {
    let isLocked: Bool
    let feature: PremiumFeature
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .opacity(isLocked ? 0.4 : 1.0)
            .disabled(isLocked)
            .overlay {
                if isLocked {
                    Button(action: action) {
                        Color.clear
                    }
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("button_\(feature.rawValue)_lock")
                    .accessibilityLabel("\(feature.displayName), Premium Feature")
                }
            }
    }
}

extension View {
    func premiumLocked(_ isLocked: Bool, feature: PremiumFeature, action: @escaping () -> Void) -> some View {
        modifier(PremiumLockedContent(isLocked: isLocked, feature: feature, action: action))
    }
}
