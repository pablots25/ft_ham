//
//  BandHopSettingsViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import SwiftUI

/// Placeholder shown for band hopping when the premium package is not linked.
public struct BandHopSettingsViewStub: View {
    public init(allowedBands: [String] = []) {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Band Hopping")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Premium Feature")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Automatic band hopping requires premium features and CAT control.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}

#if !canImport(FTHamPremium)
typealias BandHopSettingsView = BandHopSettingsViewStub
#endif
