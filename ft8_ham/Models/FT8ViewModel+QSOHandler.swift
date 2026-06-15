//
//  FT8ViewModel+QSO.swift
//  ft_ham
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

        qsoManager.isFT4Mode = isFT4
        // Start the reply in QSOManager - state is synced via computed properties
        _ = qsoManager.startReply(to: message, myCallsign: callsign, myLocator: locator)
        
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
    // State is now delegated to QSOStatusManager via computed properties.
    // We only need to observe changes for UI refresh and message regeneration.
    internal func setupQSOSubscriptions() {
        // Observe QSO state changes for message regeneration
        qsoManager.$lockedDXCallsign
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isReadyForTX = false
                self.allMessages = self.generateMessages()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        qsoManager.$lockedDXLocator
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isReadyForTX = false
                self.allMessages = self.generateMessages()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Observe SNR changes for UI updates
        qsoManager.$lastReceivedSNR
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        qsoManager.$lastSentSNR
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - QSO Reset
    @MainActor
    func resetQSOState() {
        appLogger.info("Resetting QSO state")
        qsoManager.resetQSO()
        selectedMessageIndex = 0
        // State is now managed by QSOStatusManager - no need to set here
        
        // Resume calling CQ if TX loop is active, otherwise stay idle
        if transmitLoopActive {
            qsoManager.startCallingCQ()
            isReadyForTX = true
        } else {
            isReadyForTX = false
        }
        
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
