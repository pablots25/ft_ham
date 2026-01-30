//
//  QSOLogConfirmationModifier.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 9/1/26.
//

import SwiftUI


struct QSOLogConfirmationModifier: ViewModifier {

    @ObservedObject var manager: FT8ViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                "Confirm QSO logging",
                isPresented: $manager.showConfirmQSOAlert,
                presenting: manager.pendingQSOToLog
            ) { qso in
                Button("Yes") {
                    manager.confirmLogging()
                }

                Button("No", role: .cancel) {
                    manager.cancelLogging()
                }
            } message: { qso in
                Text("Do you want to log the QSO with \(qso.callsign)?")
            }
    }
}
