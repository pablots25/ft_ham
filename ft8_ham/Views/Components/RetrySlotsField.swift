//
//  RetrySlotsField.swift
//  ft_ham
//
//  Created by GitHub Copilot on 03/04/26.
//

import SwiftUI

struct RetrySlotsField: View {
    @Binding var retries: Int

    var body: some View {
        HStack(spacing: 6) {
            TextField("Retries", value: $retries, format: .number)
                .keyboardType(.numberPad)
                .settingsCenteredInput()
                .frame(width: 50)

            Text("Retries")
                .font(.body)
                .accessibilityLabel(Text("Retransmission retries"))
                .accessibilityHint(Text("Number of times to resend messages if not acknowledged"))
        }
    }
}
