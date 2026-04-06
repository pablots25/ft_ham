//
//  CloseButton.swift
//  ft_ham
//
//  Created by GitHub Copilot on 6/4/26.
//

import SwiftUI

/// A standard Apple-style circular X dismiss button for use in sheet toolbars.
struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .accessibilityLabel("Close")
    }
}
