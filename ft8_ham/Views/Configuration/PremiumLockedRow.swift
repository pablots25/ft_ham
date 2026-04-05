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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(feature.displayName, systemImage: feature.icon)
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
