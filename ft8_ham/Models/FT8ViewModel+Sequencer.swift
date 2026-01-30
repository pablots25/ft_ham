//
//  FT8ViewModel+Sequencer.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 12/1/26.
//

import Foundation
import SwiftUI

extension FT8ViewModel {
    
    internal enum SequencerAction {
        case transmit
        case receive
        case skip
    }
    
    @MainActor
    func startSequencer() {
        guard sequencerTask == nil else { return }
        
        appLogger.info("Starting Sequencer Loop (FT\(isFT4 ? "4" : "8") - \(evenCycle ? "Even" : "Odd"))")
        isSequencerRunning = true
        
        sequencerTask = Task { [weak self] in
            guard let self else { return }
            
            self.firstLoopRX = true
            self.audioManager.startMicInput()
            self.isListening = true

            AnalyticsManager.shared.startRadioActivity(.rx)
            
            // Clear buffer initially
            self.rxBufferLock.withLock {
                self.rxSampleBuffer = Data()
            }
            
            // Ensure screen stays on
            self.updateScreenAlwaysOn()
            
            do {
                while !Task.isCancelled {
                    // 1. Calculate Next Slot Boundary
                    let now = Date()
                    let nextSlot = await self.slotManager.getNextSlot(from: now, isFT4: self.isFT4)
                    
                    // 2. Wait for Boundary
                    try await self.slotManager.wait(until: nextSlot.startTime)
                    
                    // 3. WAKE UP - CRITICAL SECTION
                    try Task.checkCancellation()
                    
                    // --- HARVEST AND DECODE PREVIOUS SLOT ---
                    // Wait a tiny bit more (200ms) to ensure the audio tap delivers the final samples of the previous slot
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    
                    let completedSlotIndex = nextSlot.slotIndex - 1
                    
                    var audioToDecode = Data()
                    var sampleCount = 0
                    
                    self.rxBufferLock.withLock {
                        audioToDecode = self.rxSampleBuffer
                        sampleCount = audioToDecode.count / 4
                    }
                    
                    // Align RX buffer exactly to slot boundary
                    self.rxBufferLock.withLock {
                        self.rxSampleBuffer = Data()
                    }
                    
                    // FT8 needs ~12.6s (151200 samples at 12k). FT4 needs ~5.0s.
                    let signalDuration = self.isFT4 ? Constants.ft4SignalDuration : Constants.ft8SignalDuration
                    let decodeMargin   = self.isFT4 ? Constants.ft4DecodeMargin : Constants.ft8DecodeMargin
                    let requiredSeconds = signalDuration + decodeMargin
                    let minSamples = Int(requiredSeconds * self.audioManager.micSampleRate)
                    
                    // Disrcard extra long buffers
                    let maxExpectedSamples = Int(
                        (signalDuration + decodeMargin + 0.05) * self.audioManager.micSampleRate
                    )

                    
                    if sampleCount >= minSamples && !self.isHarvestingRX {

                        self.rxLogger.info(
                            "Harvested \(sampleCount) samples (~\(String(format: "%.1f", Double(sampleCount) / self.audioManager.micSampleRate))s) for slot \(completedSlotIndex)"
                        )
                        
                        self.isHarvestingRX = true
                        Task {
                            let msgs = self.engine.decodeBuffer(
                                usingMonitor: audioToDecode,
                                sampleRate: self.audioManager.micSampleRate,
                                isFT4: self.isFT4
                            )
                            
                            self.rxLogger.info("Decoded \(msgs.count) messages from slot \(completedSlotIndex)")
                            await self.handleDecodedMessages(msgs)
                            
                            await MainActor.run { self.isHarvestingRX = false }
                        }
                    } else {
                        if sampleCount < minSamples {
                            self.rxLogger.debug("Buffer too small (\(sampleCount) samples). Accumulating...")
                            
                            // If it's the first loop, trigger a "Partial slot" message so the user sees
                            // the timestamp and the data loss warning immediately.
                            if self.firstLoopRX {
                                await self.handleDecodedMessages([["text": "Partial slot"]])
                            }
                        } else {
                            self.rxLogger.warning("Skipping harvest: Decode in progress")
                        }
                    }
                    
                    // 4. Determine Action
                    let action = self.determineAction(for: nextSlot)
                    
                    // 5. Execute Action
                    switch action {
                    case .transmit:
                        await self.executeTX(slot: nextSlot)
                    case .receive:
                        await self.executeRX(slot: nextSlot)
                    case .skip:
                        self.appLogger.debug("Skipping slot (Lag or Sync issue)")
                    }
                }
            } catch is CancellationError {
                self.appLogger.info("Sequencer task cancelled.")
            } catch {
                self.appLogger.error("Sequencer error: \(error.localizedDescription)")
            }
            
            // Cleanup on exit
            self.isSequencerRunning = false
            self.isListening = false
            self.isTransmitting = false
            self.sequencerTask = nil
            self.audioManager.stopPlayback()
            self.audioManager.stopMicInput()
            self.appLogger.info("Sequencer stopped clean.")
            AnalyticsManager.shared.stopRadioActivity()
        }
    }
    
    @MainActor
    func stopSequencer() {
        appLogger.info("Stopping Sequencer")
        sequencerTask?.cancel()
        sequencerTask = nil
    }
    
    @MainActor
    func restartSequencer() {
        appLogger.info("Restarting Sequencer")
        stopSequencer()

        // Do NOT auto-start unless explicitly allowed
        guard autoRXAtStart else {
            appLogger.info("Sequencer restart skipped (autoRXAtStart = false)")
            return
        }

        guard settingsLoaded else {
            appLogger.info("Sequencer restart skipped (settings not loaded)")
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            self.startSequencer()
        }
    }
    
    @MainActor
    internal func determineAction(for slot: SlotInfo) -> SequencerAction {
        if case .completed = qsoManager.qsoState {
            return .receive
        }
        
        let lag = Date().timeIntervalSince(slot.startTime)
        if lag > 2.0 {
            appLogger.error("Severe system lag detected: \(lag)s. Skipping slot \(slot.slotIndex).")
            return .skip
        }
        
        if self.transmitLoopActive {
            let isMyTurn: Bool
            switch self.txSlotPreference {
            case .followClock: isMyTurn = (slot.isEven == self.evenCycle)
            case .forceEven:   isMyTurn = slot.isEven
            case .forceOdd:    isMyTurn = !slot.isEven
            }
            
            if isMyTurn {
                appLogger.debug("Sequencer Decided: TRANSMIT (Slot \(slot.slotIndex), Even: \(slot.isEven))")
                return .transmit
            }
        }
        
        return .receive
    }
    
    @MainActor
    internal func tryImmediateTXIfPossible() async{
        let now = Date()
        
        // 1. Obtener información del slot ACTUAL
        let currentSlot = await slotManager.getSlotInfo(
            at: now,
            isFT4: isFT4
        )
        
        // 2. Calcular offset desde inicio del slot
        let offsetFromSlotStart = now.timeIntervalSince(currentSlot.startTime)
        
        let maxStartOffset = isFT4
        ? Constants.ft4MaxStartOffset
        : Constants.ft8MaxStartOffset
        
        // 3. Comprobar margen temporal
        guard offsetFromSlotStart <= maxStartOffset else {
            txLogger.debug(
                "Immediate TX skipped: offset \(String(format: "%.2f", offsetFromSlotStart))s exceeds limit"
            )
            return
        }
        
        // 4. Ver si es nuestro turno (even/odd)
        let isMyTurn: Bool
        switch txSlotPreference {
        case .followClock:
            isMyTurn = (currentSlot.isEven == evenCycle)
        case .forceEven:
            isMyTurn = currentSlot.isEven
        case .forceOdd:
            isMyTurn = !currentSlot.isEven
        }
        
        guard isMyTurn else {
            txLogger.debug("Immediate TX skipped: not our turn in this slot")
            return
        }
        
        // 5. Verificar que el TX está activo
        guard transmitLoopActive else {
            txLogger.debug("Immediate TX skipped: transmit loop not active")
            return
        }
        
        // 6. Ejecutar TX inmediato
        txLogger.info(
            "Immediate TX triggered in slot \(currentSlot.slotIndex) " +
            "(\(String(format: "%.2f", offsetFromSlotStart))s into slot)"
        )
        
        Task { @MainActor in
            await executeTX(slot: currentSlot)
        }
    }
    
    @MainActor
    internal func executeTX(slot: SlotInfo) async {
        txLogger.info("Starting transmission for slot \(slot.slotIndex)")
        self.isListening = true
        self.isTransmitting = true
        await self.performTransmission(slot: slot)
    }
    
    @MainActor
    internal func executeRX(slot: SlotInfo) async {
        rxLogger.debug("Starting reception and monitor for slot \(slot.slotIndex)")
        self.isListening = true
        self.isTransmitting = false
        
    }
    
    /// Slot-aware TX with decode barrier (no slot skipping)
    @MainActor
    internal func performTransmission(slot: SlotInfo) async {
        guard self.lastTransmittedSlotIndex != slot.slotIndex else {
            txLogger.debug("Already transmitted this slot. Skipping.")
            return
        }
        
        let now = Date()
        let offsetFromSlotStart = now.timeIntervalSince(slot.startTime)
        
        let maxStartOffset = slot.isFT4
        ? Constants.ft4MaxStartOffset
        : Constants.ft8MaxStartOffset
        
        
        // Slot-aware TX allowing late start within safe margin
        let waitStart = Date()
        
        if offsetFromSlotStart > maxStartOffset {
            txLogger.warning(
                "TX skipped for slot \(slot.slotIndex): start offset \(String(format: "%.2f", offsetFromSlotStart))s exceeds limit"
            )
            return
        }
        
        let signalEnd = slot.startTime.addingTimeInterval(
            (slot.isFT4 ? Constants.ft4SignalDuration : Constants.ft8SignalDuration) + (slot.isFT4 ? Constants.ft4DecodeMargin : Constants.ft8DecodeMargin)
        )
        while self.isHarvestingRX {
            if Date() > signalEnd {
                txLogger.warning(
                    "TX aborted for slot \(slot.slotIndex): RX decode exceeded signal window"
                )
                return
            }

            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        
        let waitedMs = Int(Date().timeIntervalSince(waitStart) * 1000)
        if waitedMs > 0 {
            txLogger.info("TX delayed \(waitedMs) ms (RX decode barrier)")
        }
        
        guard let selectedIndex = selectedMessageIndex,
              allMessages.indices.contains(selectedIndex) else {
            txLogger.warning(
                "No message selected for TX (selectedIndex: \(String(describing: selectedMessageIndex)))"
            )
            return
        }
        
        let message = allMessages[selectedIndex]
        
        guard isValidCallsign(callsign), isValidLocator(locator) else {
            audioError = "Invalid callsign/locator"
            txLogger.error("Invalid callsign/locator: \(callsign)/\(locator)")
            return
        }
        
        let txMessage = FT8Message(
            text: message,
            mode: isFT4 ? .ft4 : .ft8,
            frequency: frequency,
            isTX: true,
            band: selectedBand
        )
        
        guard let audioData = engine.generateFT8(
            message,
            frequency: Float(frequency),
            isFT4: isFT4,
            toFile: nil
        ) else {
            txLogger.error("Failed to generate audio for: \(message)")
            return
        }
        
        transmittedMessages.append(txMessage)
        txLogger.info("Added to TX list: \(message)")
        AnalyticsManager.shared.startRadioActivity(.tx)
        audioManager.playAudio(audioData)
        txLogger.info("TX Started: \(message)")
        txLogger.info(
            "TX starting \(String(format: "%.2f", offsetFromSlotStart))s into slot \(slot.slotIndex)"
        )
        
        
        self.activeTXMessage = txMessage
        self.lastTransmittedSlotIndex = slot.slotIndex
        
        // Final QSO messages (RR73 / 73) are handled by QSOStatusManager
        // Sequencer only transmits and waits for RX confirmation or courtesy RX
        if txMessage.msgType == .rr73 || txMessage.msgType == .final73 {
            appLogger.info(
                "Final QSO message transmitted — waiting for RX or courtesy timeout"
            )
            
            //            if !qsoManager.qsoAlreadyLogged {
            //                let log = qsoManager.createLogEntry(
            //                    frequency: frequency,
            //                    band: selectedBand,
            //                    isFT4: isFT4
            //                )
            //
            //                if autoQSOLogging {
            //                    handleQSOLogging(qso: log)
            //                    appLogger.info("QSO completed and logged automatically for \(dxCallsign)")
            //                } else {
            //                    pendingQSOToLog = log
            //                    showConfirmQSOAlert = true
            //                    appLogger.info("QSO completed, awaiting manual log confirmation for \(dxCallsign)")
            //                }
            //            } else {
            //                appLogger.debug("QSO already logged via RX path, skipping TX-side log")
            //            }
            //
            //            resetQSOState()
        }
    }
}

