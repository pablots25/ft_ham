//
//  CatSettingsViewStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 01/03/26.
//
//

import SwiftUI

/// Stub CAT settings view - shows premium required message
public struct CatSettingsViewStub: View {
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("CAT Control")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Premium Feature")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("CAT (Computer Aided Transceiver) control requires premium features.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()
        }
        .padding()
    }
}
