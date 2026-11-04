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
                if prompt.pendingQSOIsUnconfirmed {
                    Text("The QSO with \(qso.callsign) timed out before the final 73, but both signal reports were exchanged. Log it anyway?")
                } else {
                    Text("Do you want to log the QSO with \(qso.callsign)?")
                }
            }
    }
}
