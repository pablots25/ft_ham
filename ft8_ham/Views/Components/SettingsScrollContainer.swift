//
//  SettingsScrollContainer.swift
//  ft_ham
//
//  Created by GitHub Copilot on 03/04/26.
//

import SwiftUI

struct SettingsScrollContainer<Content: View>: View {
    let title: LocalizedStringKey
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    let contentBottomPadding: CGFloat
    let dismissKeyboardOnScroll: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 20,
        contentBottomPadding: CGFloat = 0,
        dismissKeyboardOnScroll: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.spacing = spacing
        self.contentBottomPadding = contentBottomPadding
        self.dismissKeyboardOnScroll = dismissKeyboardOnScroll
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        let base = ScrollView {
            VStack(alignment: alignment, spacing: spacing) {
                content()
            }
            .padding(.horizontal)
            .padding(.bottom, contentBottomPadding)
        }
        .navigationTitle(title)

        #if os(iOS)
        let styled = base.navigationBarTitleDisplayMode(.inline)
        if dismissKeyboardOnScroll {
            styled.scrollDismissesKeyboard(.interactively)
        } else {
            styled
        }
        #else
        base
        #endif
    }
}
