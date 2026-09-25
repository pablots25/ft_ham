//
//  QSOLogExtension.swift
//  ft_ham
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
        pendingQSOIsUnconfirmed = false
        logAction = nil
        showConfirmQSOAlert = false
    }

    /// Manually logs the QSO currently in progress, for when the operator is
    /// confident it completed but the other station never sent the closing
    /// RR73/73 (so auto-sequencing is still retrying or waiting). Builds the
    /// entry from the live QSO state — missing signal reports are recorded as
    /// "Invalid" — routes it through the confirmation prompt, then ends the QSO.
    @MainActor
    func forceLogCurrentQSO() {
        guard !qsoManager.lockedDXCallsign.isEmpty else {
            appLogger.warning("forceLogCurrentQSO: no QSO in progress")
            return
        }

        let entry = qsoManager.createLogEntry(
            dxCallsign: qsoManager.lockedDXCallsign,
            dxLocator: qsoManager.lockedDXLocator,
            qsoDate: AppClock.now(),
            band: qsoManager.qsoStartBand ?? effectiveBand,
            isFT4: qsoManager.qsoStartedAsFT4,
            rstSent: qsoManager.lastSentSNR,
            rstRcvd: qsoManager.lastReceivedSNR,
            customFrequencyHz: qsoManager.qsoStartBand != nil
                ? qsoManager.qsoStartCustomFrequencyHz
                : (selectedBand == .custom ? customDialFrequencyHz : nil)
        )

        // Stop auto-sequencing from also logging/continuing this QSO, then end it.
        qsoManager.qsoAlreadyLogged = true
        invalidatePendingTX(reason: "manual force-log")
        dxCallsign = ""
        dxLocator = ""
        selectedMessageIndex = 0
        resetQSOState()

        // Always confirm a manually forced log (it is, by definition, incomplete).
        offerLogging(qso: entry, unconfirmed: true)
    }

    func handleQSOLogging(qso: LogEntry) {
        if autoQSOLogging {
             appLogger.info("Automatic log for \(dxCallsign)")
            logQSO(qso: qso)
        } else {
            pendingQSOIsUnconfirmed = false
            pendingQSOToLog = qso
            logAction = logQSO
            showConfirmQSOAlert = true
            appLogger.info("Awaiting manual log confirmation for \(qso.callsign)")
        }
    }

    /// Always prompts the operator to confirm logging, regardless of the
    /// autoQSOLogging setting. Used for QSOs that timed out before the final
    /// handshake — the reports were exchanged but the contact is unconfirmed,
    /// so it should never be logged silently.
    func offerLogging(qso: LogEntry, unconfirmed: Bool) {
        pendingQSOIsUnconfirmed = unconfirmed
        pendingQSOToLog = qso
        logAction = logQSO
        showConfirmQSOAlert = true
        appLogger.info("Offering manual log for \(qso.callsign) (unconfirmed: \(unconfirmed))")
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
        Task { @MainActor in
            InAppPrompts.shared.recordQSOLogged()
        }

        // Trigger log sync (QRZ / LoTW upload if enabled)
        LogSyncManager.shared.syncNewQSO(qso)
        CloudLogbookSyncManager.shared.syncNewQSO(qso)

        // Show persistent local notification
        let content = UNMutableNotificationContent()
        content.title = "QSO Completed ✅"
        content.body = "QSO with \(qso.callsign) has been logged successfully."
        content.sound = .default
        content.categoryIdentifier = NotificationHelper.qsoLoggedCategoryID

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

        qsoManager.qsoAlreadyLogged = true // TODO - Review if needed
        finalizeQSOAfterLogging()
    }

    
    internal func finalizeQSOAfterLogging() {
        appLogger.info("Finalizing QSO after logging")

        pendingQSOToLog = nil
        pendingQSOIsUnconfirmed = false
        logAction = nil
        showConfirmQSOAlert = false
    }

}
