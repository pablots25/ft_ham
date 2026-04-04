//
//  SettingsInputModifiers.swift
//  ft_ham
//
//  Created by GitHub Copilot on 03/04/26.
//

import SwiftUI

extension View {
    func settingsCenteredInput() -> some View {
        self
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .lineLimit(1)
    }

    func settingsCenteredTextInput() -> some View {
        self
            .settingsCenteredInput()
            .autocorrectionDisabled()
    }

    func settingsTrailingTextInput() -> some View {
        self
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
    }
}
