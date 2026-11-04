//
//  CatDebugViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/04/26.
//

import SwiftUI

/// Stub CAT debug view shown when the premium package is not available.
public struct CatDebugViewStub: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("CAT Debug")
                .font(.headline)

            Text("Premium Feature")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("CAT command history requires the premium package.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
