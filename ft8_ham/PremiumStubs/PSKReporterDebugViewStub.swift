//
//  PSKReporterDebugViewStub.swift
//  ft8_ham
//
//  Stub view for public-only builds
//  Premium implementation is in private ft_ham_premium package
//
//  Created on 01/03/26.
//

import SwiftUI

/// Stub PSK Reporter debug view - shows premium required message
public struct PSKReporterDebugViewStub: View {
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("PSK Reporter Debug")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Premium Feature")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("PSK Reporter debugging requires premium features.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()
        }
        .padding()
    }
}
