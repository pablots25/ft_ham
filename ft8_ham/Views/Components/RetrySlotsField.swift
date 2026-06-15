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
        Stepper(value: $retries, in: 1...10) {
            HStack {
                Text("Retries")
                Spacer()
                Text("\(retries)")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text("Retransmission retries"))
        .accessibilityHint(Text("Number of times to resend messages if not acknowledged"))
    }
}
