//
//  FT8ViewModel+FreeText.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation

// MARK: - Free-text TX loop
//
// A free-text message is transmitted on every "my turn" slot until stopped.
// It lives outside the QSO state machine: nothing is expected back, nothing
// is logged, and the QSO manager is not advanced when the audio finishes.

extension FT8ViewModel {

    /// The text that will go on the air, after sanitising.
    var freeTextForTX: String {
        FreeTextMessage.sanitize(freeTextMessage)
    }

    /// True when the current free text can be transmitted.
    var canStartFreeTextLoop: Bool {
        if case .success = FreeTextMessage.validate(freeTextForTX) { return settingsLoaded }
        return false
    }

    @MainActor
    func startFreeTextLoop() {
        guard case .success(let text) = FreeTextMessage.validate(freeTextForTX) else {
            txLogger.warning("Free text loop not started: text is invalid")
            return
        }
        // The two loops are mutually exclusive; the QSO loop yields.
        if transmitLoopActive {
            toggleTransmit()
        }
        freeTextLoopActive = true
        invalidatePendingTX(reason: "free text loop enabled")
        appLogger.info("Free text loop enabled: '\(text)'")
        if sequencerTask == nil {
            startSequencer()
        }
    }

    @MainActor
    func stopFreeTextLoop() {
        guard freeTextLoopActive else { return }
        freeTextLoopActive = false
        appLogger.info("Free text loop disabled")
    }

    @MainActor
    func toggleFreeTextLoop() {
        if freeTextLoopActive {
            stopFreeTextLoop()
        } else {
            startFreeTextLoop()
        }
    }
}
