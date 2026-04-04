//
//  QRZSettingsViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 04/04/26.
//

import SwiftUI

/// Stub QRZ settings view — shown only when premium package is not linked.
public struct QRZSettingsViewStub: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("QRZ Logbook Integration")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Premium Feature")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Automatic QSO upload, confirmation sync and ADIF import from QRZ Logbook require a premium subscription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
        }
        .padding()
    }
}
