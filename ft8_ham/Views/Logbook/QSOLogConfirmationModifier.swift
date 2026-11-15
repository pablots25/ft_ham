//
//  QSOLogConfirmationModifier.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/1/26.
//

import SwiftUI


struct QSOLogConfirmationModifier: ViewModifier {

    /// Not observed: this modifier sits above `ContentView`, so observing the
    /// whole view model here would re-evaluate the entire app on every publish.
    let manager: FT8ViewModel
    @ObservedObject private var prompt: QSOLogPrompt

    init(manager: FT8ViewModel) {
        self.manager = manager
        self._prompt = ObservedObject(wrappedValue: manager.logPrompt)
    }

    func body(content: Content) -> some View {
        content
            .alert(
                prompt.pendingQSOIsUnconfirmed
                    ? "Log incomplete QSO?"
                    : "Confirm QSO logging",
                isPresented: $prompt.showConfirmQSOAlert,
                presenting: prompt.pendingQSOToLog
            ) { qso in
                Button("Yes") {
                    manager.confirmLogging()
                }

                Button("No", role: .cancel) {
                    manager.cancelLogging()
                }
            } message: { qso in
                Self.messageText(for: QSOLogPromptMessage.make(reason: prompt.pendingReason, qso: qso), callsign: qso.callsign)
            }
    }

    private static func messageText(for message: QSOLogPromptMessage, callsign: String) -> Text {
        switch message {
        case .confirm:
            Text("Do you want to log the QSO with \(callsign)?")
        case .timedOut:
            Text("The QSO with \(callsign) timed out before the final 73, but both signal reports were exchanged. Log it anyway?")
        case .manualBothReports:
            Text("Both signal reports were exchanged with \(callsign), but the final 73 has not arrived. Log it anyway?")
        case .missingReceivedReport:
            Text("No signal report received from \(callsign). It will be logged without the received report. Log it anyway?")
        case .missingSentReport:
            Text("No signal report sent to \(callsign). It will be logged without the sent report. Log it anyway?")
        case .missingBothReports:
            Text("No signal reports were exchanged with \(callsign). It will be logged without reports. Log it anyway?")
        }
    }
}
