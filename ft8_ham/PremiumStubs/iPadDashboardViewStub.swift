//
//  iPadDashboardViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/04/26.
//

import SwiftUI

/// Stub iPad Dashboard view — shown only when premium package is not linked.
public struct iPadDashboardViewStub: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("iPad Dashboard")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Premium Feature")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("The multi-panel iPad dashboard layout requires a premium subscription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
        }
        .padding()
    }
}
