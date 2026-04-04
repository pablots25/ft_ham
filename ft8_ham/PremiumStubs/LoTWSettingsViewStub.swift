//
//  LoTWSettingsViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import SwiftUI

/// Stub LoTW settings view — shown only when premium package is not linked.
public struct LoTWSettingsViewStub: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("LoTW Integration")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Premium Feature")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Automatic QSO upload and confirmation sync with ARRL Logbook of the World (LoTW) require a premium subscription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
        }
        .padding()
    }
}
