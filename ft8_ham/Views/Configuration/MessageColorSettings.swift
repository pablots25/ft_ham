//
//  MessageColorSettings.swift
//  ft_ham
//
//  Created by Pablo Turrion on 22/09/26.
//

import SwiftUI

/// One color picker per kind of decoded row, plus a reset to the defaults.
struct MessageColorSettings: View {
    @ObservedObject private var store = RowColorStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MessageRowColor.allCases) { kind in
                ColorPicker(
                    selection: Binding(
                        get: { store.color(kind) },
                        set: { store.setColor($0, for: kind) }
                    ),
                    supportsOpacity: false
                ) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(store.tint(kind))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(store.color(kind).opacity(0.7), lineWidth: 1.5)
                            )
                            .frame(width: 28, height: 16)
                            .accessibilityHidden(true)
                        Text(kind.label)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("colorPicker_\(kind.rawValue)")
            }

            Button("Reset colors", role: .destructive) {
                store.resetToDefaults()
            }
            .disabled(!store.isCustomized)
            .accessibilityIdentifier("button_resetRowColors")
        }
        .padding(.top, 6)
    }
}
