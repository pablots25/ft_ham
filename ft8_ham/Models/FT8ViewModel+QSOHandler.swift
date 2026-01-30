//
//  FT8ViewModel+QSO.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 12/1/26.
//

import Foundation

extension FT8ViewModel {
    
    // MARK: - Reply Management
    @MainActor
    func reply(to message: FT8Message) {
        appLogger.info("Initializing reply to \(message.callsign ?? "unknown")")
        
        alignTXFrequencyForQSOStart(from: message)
        
        let action = qsoManager.startReply(to: message, myCallsign: callsign, myLocator: locator)
        
        dxCallsign = qsoManager.lockedDXCallsign
        dxLocator = qsoManager.lockedDXLocator
        lastSentSNR = message.measuredSNR
        
        self.autoSequencingEnabled = true
        if autoSequencingEnabled {
            appLogger.info("Auto-sequencing enabled, determining initial message index for reply")
            selectedMessageIndex = 1 // TX1: Grid
        }
        
        txSlotPreference = (message.cycle == .even) ? .forceOdd : .forceEven
        invalidatePendingTX(reason: "Reply slot alignment")
        
        allMessages = generateMessages()
        
        if !transmitLoopActive {
            self.toggleTransmit()
        }
        
        self.isReadyForTX = true
        
        appLogger.log(
            .info,
            "Reply initialized for DX=\(dxCallsign) in \(evenCycle ? "even" : "odd") cycle (synced to message slot)"
        )

        // NEW: try immediate TX inside current slot if possible
        self.lastTransmittedSlotIndex = nil
        
        Task { @MainActor in
            await tryImmediateTXIfPossible()
        }

        appLogger.log(
            .info,
            "QSO sequence started: state=\(qsoManager.qsoState), messageIndex=\(selectedMessageIndex ?? -1)"
        )
    }
    
    // MARK: - QSO Subscriptions
    internal func setupQSOSubscriptions() {
        qsoManager.$lockedDXCallsign
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCall in
                guard let self else { return }
                guard self.dxCallsign != newCall else { return }
                self.dxCallsign = newCall
                self.isReadyForTX = false
                self.allMessages = self.generateMessages()
            }
            .store(in: &cancellables)

        qsoManager.$lockedDXLocator
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLoc in
                guard let self else { return }
                guard self.dxLocator != newLoc else { return }
                self.dxLocator = newLoc
                self.isReadyForTX = false
                self.allMessages = self.generateMessages()
            }
            .store(in: &cancellables)

        qsoManager.$lastReceivedSNR
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSNR in
                guard let self else { return }
                self.lastReceivedSNR = Double(newSNR)
            }
            .store(in: &cancellables)
        
        qsoManager.$lastSentSNR
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSNR in
                guard let self else { return }
                self.lastSentSNR = Double(newSNR)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - QSO Reset
    @MainActor
    func resetQSOState() {
        appLogger.info("Resetting QSO state")
        qsoManager.resetQSO()
        selectedMessageIndex = 0
        dxCallsign = ""
        dxLocator = ""
        lastSentSNR = Double(Int.min)
        lastReceivedSNR = Double(Int.min)
        isReadyForTX = true
        
        invalidatePendingTX(reason: "QSO reset")
    }
    
    // MARK: - Pending TX Management
    internal func invalidatePendingTX(reason: String) {
        txLogger.log(.debug, "Invalidating pending TX: \(reason)")
        
        // This causes the transmit loop to regenerate the wav for the next slot
        // since pendingTXMessageVersion will be different from lastHandledTXMessageVersion
        self.pendingTXMessageVersion += 1
        self.lastTransmittedSlotIndex = nil
        self.currentTXRetryCount = 0
        self.lastTXVersionRetried = nil
    }
}
