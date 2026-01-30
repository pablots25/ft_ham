//
//  QSOLogExtension.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 9/1/26.
//

import UserNotifications

extension FT8ViewModel  {
    
    func confirmLogging() {
        guard let qso = pendingQSOToLog else { return }
        logQSO(qso: qso)
    }

    func cancelLogging() {
        pendingQSOToLog = nil
        logAction = nil
        showConfirmQSOAlert = false
    }
    
    func handleQSOLogging(qso: LogEntry) {
        if autoQSOLogging {
             appLogger.info("Automatic log for \(dxCallsign)")
            logQSO(qso: qso)
        } else {
            pendingQSOToLog = qso
            logAction = logQSO
            showConfirmQSOAlert = true
            appLogger.info("Awaiting manual log confirmation for \(qso.callsign)")
        }
    }
    
    private func finalizeLogging() {
        pendingQSOToLog = nil
        logAction = nil
        showConfirmQSOAlert = false
    }


    private func logQSO(qso: LogEntry) {
        appLogger.log(.info, "QSO with \(qso.callsign) successfully completed.")
        qsoList.append(qso)
        AnalyticsManager.shared.addQSOs()

        // Show persistent local notification
        let content = UNMutableNotificationContent()
        content.title = "QSO Completed ✅"
        content.body = "QSO with \(qso.callsign) has been logged successfully."
        content.sound = .default
        content.badge = NSNumber(value: qsoList.count)
        content.categoryIdentifier = "QSO_CATEGORY"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, // unique identifier
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.appLogger
                    .log(
                        .error,
                        "Error showing notification: \(error.localizedDescription)"
                    )
            }
        }

        // Define actions and category for persistent notifications
        let reviewAction = UNNotificationAction(
            identifier: "REVIEW_QSO",
            title: "Review QSO",
            options: [.foreground] // opens the app when tapped
        )

        let category = UNNotificationCategory(
            identifier: "QSO_CATEGORY",
            actions: [reviewAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])

        qsoManager.qsoAlreadyLogged = true // TODO - Review if needed
        finalizeQSOAfterLogging()
    }

    
    internal func finalizeQSOAfterLogging() {
        appLogger.info("Finalizing QSO after logging")

        pendingQSOToLog = nil
        logAction = nil
        showConfirmQSOAlert = false
    }

}
