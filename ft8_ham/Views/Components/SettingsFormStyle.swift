//
//  SettingsFormStyle.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

// MARK: - Shared Form Styling for Settings Sub-screens

struct SettingsFormStyle: ViewModifier {
    let title: LocalizedStringKey

    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func settingsFormStyle(title: LocalizedStringKey) -> some View {
        modifier(SettingsFormStyle(title: title))
    }
}
