//
//  DonationPremiumPromptView.swift
//  ft_ham
//
//  Created by GitHub Copilot on 6/4/26.
//

import SwiftUI

struct DonationPremiumPromptView: View {
    @EnvironmentObject private var premiumManager: PremiumManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)

            VStack(spacing: 12) {
                Text("Thank You for Your Support!")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("As a donor, you now have full access to all premium features — at no extra cost.\n\nYour contribution helps keep FT Ham growing. 73!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                premiumManager.didShowDonationPremiumPrompt = true
                dismiss()
            } label: {
                Text("Got It!")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }
}
