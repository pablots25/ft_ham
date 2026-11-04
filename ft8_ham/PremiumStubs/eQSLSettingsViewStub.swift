//
//  eQSLSettingsViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/04/26.
//

import SwiftUI

/// Stub eQSL settings view — shown only when premium package is not linked.
public struct eQSLSettingsViewStub: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("eQSL Integration")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Premium Feature")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Automatic QSO upload to eQSL.cc requires a premium subscription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
        }
        .padding()
    }
}
