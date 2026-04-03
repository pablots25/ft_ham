//
//  FirstRunChecklistView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI

struct FirstRunChecklistView: View {
    @AppStorage("callsign") private var callsign: String = ""
    @AppStorage("locator") private var locator: String = ""
    @AppStorage("hasStartedRX") private var hasStartedRX: Bool = false
    @AppStorage("hasSeenFirstDecode") private var hasSeenFirstDecode: Bool = false

    /// When shown inside the onboarding flow (page 10) we skip the note.
    var isEmbedded: Bool = false

    private var callsignDone: Bool { !callsign.isEmpty && !locator.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("checklist_title")
                .font(.headline)
                .padding(.bottom, 2)

            checklistRow(done: callsignDone, labelKey: "checklist_step_callsign")
            checklistRow(done: hasStartedRX, labelKey: "checklist_step_startrx")
            checklistRow(done: hasSeenFirstDecode, labelKey: "checklist_step_firstdecode")

            if !isEmbedded {
                Text("checklist_note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func checklistRow(done: Bool, labelKey: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.system(size: 20))
            Text(labelKey)
                .strikethrough(done, color: .secondary)
                .foregroundStyle(done ? .secondary : .primary)
        }
    }
}

#Preview("FirstRunChecklistView") {
    FirstRunChecklistView(isEmbedded: false)
        .padding()
}
