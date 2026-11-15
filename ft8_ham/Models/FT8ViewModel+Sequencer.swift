//
//  FT8ViewModel+Sequencer.swift
//  ft_ham
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
        guard settingsLoaded else {
            appLogger.warning("startSequencer called with invalid settings (callsign/locator). Aborting.")
            return
        }
        appLogger.info("Starting Sequencer Loop (FT\(isFT4 ? "4" : "8") - \(evenCycle ? "Even" : "Odd"))")
        isSequencerRunning = true
        PresenceManager.shared.sequencerDidStart(
            callsign: callsign, grid: locator,
            band: effectiveBand.rawValue, mode: isFT4 ? "FT4" : "FT8"
        )

        // Track first-run milestone
        UserDefaults.standard.set(true, forKey: "hasStartedRX")
        
        sequencerTask = Task { [weak self] in
            guard let self else { return }
            
            self.firstLoopRX = true
            self.audioManager.startMicInput()
            self.isListening = true

            AnalyticsManager.shared.startRadioActivity(.rx)
            
            // Whatever was analysed before belongs to no slot.
            self.slotMonitor.resetSlot()
            
            // Ensure screen stays on
            self.updateScreenAlwaysOn()
            
            do {
                while !Task.isCancelled {
                    // 1. Calculate Next Slot Boundary
                    let now = AppClock.now()
                    let nextSlot = await self.slotManager.getNextSlot(from: now, isFT4: self.isFT4)
                    
                    // 2. Wait for Boundary
                    try await self.slotManager.wait(until: nextSlot.startTime)

                    // 3. WAKE UP - CRITICAL SECTION
                    try Task.checkCancellation()

                    // How late the loop got back to the main actor. The rest of
                    // any lag seen in determineAction is the harvest below.
                    let wakeLag = AppClock.now().timeIntervalSince(nextSlot.startTime)
                    
                    // --- HARVEST AND DECODE PREVIOUS SLOT ---
                    // The slot monitor has been analysing the audio as it
                    // arrived; take that spectrogram and start the next slot's
                    // in one step, so the new slot's block 0 sits on the boundary.
                    // When this wake-up comes late (the system delays the app
                    // in the background) the monitor has already cut the slot
                    // at its boundary on the audio's own time; that snapshot
                    // says which slot it holds.
                    let snapshot = self.slotMonitor.snapshotAndReset(forSlot: Int64(nextSlot.slotIndex - 1))
                    let completedSlotIndex = snapshot.slotIndex >= 0
                        ? Int(snapshot.slotIndex)
                        : nextSlot.slotIndex - 1
                    if snapshot.slotIndex >= 0 {
                        self.rxLogger.debug(
                            "Slot \(completedSlotIndex) was cut at its boundary before the sequencer woke up"
                        )
                    }
                    let coveredSeconds = snapshot.duration

                    // FT8 needs ~12.6s of signal. FT4 needs ~4.5s.
                    let signalDuration = self.isFT4 ? Constants.ft4SignalDuration : Constants.ft8SignalDuration
                    let decodeMargin   = self.isFT4 ? Constants.ft4DecodeMargin : Constants.ft8DecodeMargin
                    let requiredSeconds = signalDuration + decodeMargin

                    // Guard: micSampleRate starts at 0 and is populated lazily by startMicInput().
                    // Until then no audio has reached the monitor, so there is nothing to decode.
                    guard self.audioManager.micSampleRate > 0 else {
                        self.rxLogger.warning("Skipping decode (slot \(completedSlotIndex)): micSampleRate not yet initialized")
                        continue
                    }

                    if coveredSeconds >= requiredSeconds && !self.isHarvestingRX {

                        self.rxLogger.info(
                            "Harvested \(String(format: "%.1f", coveredSeconds))s of spectrogram for slot \(completedSlotIndex)"
                        )

                        // Capture @MainActor values before spawning the detached task so the
                        // CPU-intensive decode runs on a background thread, not the main thread.
                        let capturedEngine = self.engine
                        let capturedIsFT4 = self.isFT4
                        let capturedLogger = self.rxLogger
                        self.isHarvestingRX = true
                        Task.detached(priority: .userInitiated) { [weak self] in
                            let weakSelf = self
                            defer { Task { await MainActor.run { weakSelf?.isHarvestingRX = false } } }

                            let msgs = capturedEngine.decodeWaterfallSnapshot(snapshot, isFT4: capturedIsFT4)

                            capturedLogger.info("Decoded \(msgs.count) messages from slot \(completedSlotIndex)")
                            await weakSelf?.handleDecodedMessages(
                                msgs, slotIndex: completedSlotIndex, slotSequence: UInt(snapshot.slotSequence)
                            )
                        }
                    } else {
                        if coveredSeconds < requiredSeconds {
                            self.rxLogger.debug("Slot too short (\(String(format: "%.1f", coveredSeconds))s). Accumulating...")
                            
                            // If it's the first loop, trigger a "Partial slot" message so the user sees
                            // the timestamp and the data loss warning immediately.
                            if self.firstLoopRX {
                                await self.handleDecodedMessages([["text": "Partial slot"]], slotIndex: completedSlotIndex)
                            }
                        } else {
                            self.rxLogger.warning("Skipping harvest: Decode in progress")
                        }
                    }
                    
                    // 4. Determine Action
                    let action = self.determineAction(for: nextSlot, wakeLag: wakeLag)
                    
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
            PresenceManager.shared.sequencerDidStop()
            self.isListening = false
            self.isTransmitting = false
            self.freeTextLoopActive = false
            self.sequencerTask = nil
            self.audioManager.stopPlayback()
            self.audioManager.stopMicInput()
            self.appLogger.info("Sequencer stopped clean.")
            AnalyticsManager.shared.stopRadioActivity(outcome: .interrupted(.sequencerStopped))
        }
    }
    
    @MainActor
    func stopSequencer(rememberState: Bool = false) async {
        appLogger.info("Stopping Sequencer")
        let task = sequencerTask

        if rememberState {
            wasSequencerRunningBeforeBackground = isSequencerRunning || task != nil
        }

        guard let task else { return }

        task.cancel()
        await task.value
    }
    
    @MainActor
    func restartSequencer() async {
        appLogger.info("Restarting Sequencer")
        await stopSequencer()

        // Do NOT auto-start unless explicitly allowed
        guard autoRXAtStart else {
            appLogger.info("Sequencer restart skipped (autoRXAtStart = false)")
            return
        }

        guard settingsLoaded else {
            appLogger.info("Sequencer restart skipped (settings not loaded)")
            return
        }

        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        self.startSequencer()
    }
    
    /// Lag past the slot start beyond which the slot is skipped.
    nonisolated static let maxSlotLag: TimeInterval = 2.0

    /// `true` when `lag` covers at least a whole slot (15 s FT8, 7.5 s FT4).
    /// That only happens when the app was suspended and resumed, so it is
    /// logged as a warning instead of a Crashlytics non-fatal.
    nonisolated static func isSuspensionGap(lag: TimeInterval, isFT4: Bool) -> Bool {
        lag >= (isFT4 ? 7.5 : 15.0)
    }

    /// `true` when a late slot says nothing about the app's performance. A stall
    /// with the app active and less than a whole slot late is the only real one.
    nonisolated static func isExpectedSlotLag(
        lag: TimeInterval,
        isFT4: Bool,
        applicationState: UIApplication.State
    ) -> Bool {
        applicationState != .active || isSuspensionGap(lag: lag, isFT4: isFT4)
    }

    /// How a slot that arrived late gets logged.
    enum SlotLagSeverity: Equatable {
        /// On time, or within `maxSlotLag`.
        case onTime
        /// Suspension or not active: the system delayed the app. Warning.
        case expected
        /// A real stall, but nothing was due to transmit, so RX loses nothing:
        /// the slot monitor keeps capturing audio. Warning.
        case receiveStall
        /// A real stall that cost a transmission. Crashlytics non-fatal.
        case transmitStall
    }

    nonisolated static func slotLagSeverity(
        lag: TimeInterval,
        isFT4: Bool,
        applicationState: UIApplication.State,
        transmitDue: Bool
    ) -> SlotLagSeverity {
        guard lag > maxSlotLag else { return .onTime }
        if isExpectedSlotLag(lag: lag, isFT4: isFT4, applicationState: applicationState) {
            return .expected
        }
        return transmitDue ? .transmitStall : .receiveStall
    }

    /// Splits a lag into the wake-up from the slot wait and the main-actor work
    /// after it, e.g. `wake 0.012s, harvest 2.301s`. A late wake points at the
    /// timer or a busy main actor; a long harvest points at the work done before
    /// `determineAction`. Without `wakeLag` (tests) only the total is known.
    nonisolated static func lagBreakdown(lag: TimeInterval, wakeLag: TimeInterval?) -> String {
        guard let wakeLag else { return "phases unknown" }
        let harvest = max(0, lag - wakeLag)
        return String(format: "wake %.3fs, harvest %.3fs", wakeLag, harvest)
    }

    nonisolated static func stateDescription(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    @MainActor
    internal func determineAction(for slot: SlotInfo, wakeLag: TimeInterval? = nil) -> SequencerAction {
        if case .completed = qsoManager.qsoState {
            return .receive
        }

        let lag = AppClock.now().timeIntervalSince(slot.startTime)
        if lag > Self.maxSlotLag {
            logLateSlot(slot, lag: lag, wakeLag: wakeLag)
            return .skip
        }

        guard isTransmitDue(slot) else { return .receive }

        if !self.freeTextLoopActive {
            // Clear isReadyForTX after using it to prevent repeated TX
            self.isReadyForTX = false
            appLogger.debug("Sequencer Decided: TRANSMIT (Slot \(slot.slotIndex), Even: \(slot.isEven))")
        }
        return .transmit
    }

    /// `true` when this slot would transmit if it were on time. No side effects.
    @MainActor
    internal func isTransmitDue(_ slot: SlotInfo) -> Bool {
        guard isMyTurn(slot) else { return false }
        // Free text runs outside the QSO state machine: every my-turn slot.
        if self.freeTextLoopActive { return true }
        // Only TX when: calling CQ, in a "sending" state, or isReadyForTX (immediate response)
        return (self.transmitLoopActive && qsoManager.shouldTransmitThisSlot()) || self.isReadyForTX
    }

    @MainActor
    private func logLateSlot(_ slot: SlotInfo, lag: TimeInterval, wakeLag: TimeInterval?) {
        let state = applicationState()
        let severity = Self.slotLagSeverity(
            lag: lag, isFT4: slot.isFT4, applicationState: state, transmitDue: isTransmitDue(slot)
        )
        let phases = Self.lagBreakdown(lag: lag, wakeLag: wakeLag)

        switch severity {
        case .onTime:
            return
        case .expected:
            // The app was suspended or is not active, so the system can
            // delay it. Expected, not a bug.
            appLogger.warning(
                "Slot \(slot.slotIndex) skipped (\(lag)s late, \(phases), app state: \(Self.stateDescription(state)))"
            )
        case .receiveStall:
            // RX keeps capturing through a skipped slot, so nothing is lost.
            appLogger.warning("RX slot \(slot.slotIndex) late: \(lag)s (\(phases)).")
        case .transmitStall:
            appLogger.error(
                "Severe system lag detected: \(lag)s (\(phases)). Skipping TX slot \(slot.slotIndex)."
            )
        }
    }
    
    /// Drops audio captured so far in this slot (e.g. after a band hop, so the
    /// next decode does not mix two bands).
    @MainActor
    internal func clearRXBuffer() {
        slotMonitor.resetSlot()
    }

    /// Slot parity check shared by the QSO and free-text loops.
    @MainActor
    internal func isMyTurn(_ slot: SlotInfo) -> Bool {
        switch self.txSlotPreference {
        case .followClock: return slot.isEven == self.evenCycle
        case .forceEven:   return slot.isEven
        case .forceOdd:    return !slot.isEven
        }
    }

    @MainActor
    internal func tryImmediateTXIfPossible() async{
        let now = AppClock.now()
        
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
        if !isListening { isListening = true }
        if !isTransmitting { isTransmitting = true }
        await self.performTransmission(slot: slot)
    }
    
    @MainActor
    internal func executeRX(slot: SlotInfo) async {
        rxLogger.debug("Starting reception and monitor for slot \(slot.slotIndex)")
        if !isListening { isListening = true }
        if isTransmitting { isTransmitting = false }
        
    }
    
    /// Slot-aware TX with decode barrier (no slot skipping)
    @MainActor
    internal func performTransmission(slot: SlotInfo) async {
        guard self.lastTransmittedSlotIndex != slot.slotIndex else {
            txLogger.debug("Already transmitted this slot. Skipping.")
            return
        }
        
        let now = AppClock.now()
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
            if AppClock.now() > signalEnd {
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
        
        let message: String
        let audioData: Data
        let isFreeText = freeTextLoopActive

        if isFreeText {
            guard case .success(let text) = FreeTextMessage.validate(freeTextForTX) else {
                txLogger.warning("Free text TX skipped: text is invalid")
                freeTextLoopActive = false
                return
            }
            guard isValidCallsign(callsign) else {
                audioError = "Invalid callsign/locator"
                txLogger.warning("Invalid callsign: \(callsign)")
                return
            }
            guard let data = engine.generateFreeText(text, frequency: Float(frequency), isFT4: isFT4) else {
                txLogger.error("Failed to generate free text audio for: \(text)")
                audioError = Constants.audioGenerationFailedMessage
                return
            }
            message = text
            audioData = data
        } else {
            guard let selectedIndex = selectedMessageIndex,
                  allMessages.indices.contains(selectedIndex) else {
                txLogger.warning(
                    "No message selected for TX (selectedIndex: \(String(describing: selectedMessageIndex)))"
                )
                return
            }

            message = allMessages[selectedIndex]
            txLogger.debug("TX message selection: index=\(selectedIndex), message='\(message)', dxCallsign='\(dxCallsign)'")

            guard isValidCallsign(callsign), isValidLocator(locator) else {
                // Station setup problem, not a bug: the user sees audioError.
                audioError = "Invalid callsign/locator"
                txLogger.warning("Invalid callsign/locator: \(callsign)/\(locator)")
                return
            }

            guard let data = engine.generateFT8(
                message,
                frequency: Float(frequency),
                isFT4: isFT4,
                toFile: nil
            ) else {
                txLogger.error("Failed to generate audio for: \(message)")
                audioError = Constants.audioGenerationFailedMessage
                return
            }
            audioData = data
        }

        let txMessage = FT8Message(
            text: message,
            mode: isFT4 ? .ft4 : .ft8,
            frequency: frequency,
            isTX: true,
            band: selectedBand
        )
        
        transmittedMessages.append(txMessage)
        txLogger.info("Added to TX list: \(message)")
        
        // Clear isReadyForTX after successful TX preparation
        self.isReadyForTX = false
        
        // The scenePhase handler stops the sequencer on backgrounding, but a TX
        // task already in flight can reach this point afterwards. Starting audio
        // in the background has no IO cycle and crashes AVAudioPlayerNode.
        // A Mac keeps the audio engine running while hidden, so the policy
        // lets TX go ahead there.
        guard applicationState() != .background || keepsRadioRunningInBackground() else {
            txLogger.warning("TX skipped for slot \(slot.slotIndex): app is in background")
            return
        }

        AnalyticsManager.shared.startRadioActivity(.tx)
        sendCatFrequency(reason: "tx start")
        setCatPTT(true, reason: "tx start")
        audioManager.playAudio(audioData)
        // playAudio sets isPlaying synchronously. Still false means the engine
        // refused the buffer, so this TX never went on air.
        if !audioManager.isPlaying {
            AnalyticsManager.shared.interruptTransmission(.playbackFailed)
        }
        InAppPrompts.shared.recordTXStarted()
        txLogger.info("TX Started: \(message)")
        txLogger.info(
            "TX starting \(String(format: "%.2f", offsetFromSlotStart))s into slot \(slot.slotIndex)"
        )
        
        
        self.activeTXMessage = txMessage
        self.activeTXIsFreeText = isFreeText
        self.lastTransmittedSlotIndex = slot.slotIndex
        
        // Final QSO messages (RR73 / 73) are handled by QSOStatusManager
        // Sequencer only transmits and waits for RX confirmation or courtesy RX
        if txMessage.msgType == .rr73 || txMessage.msgType == .final73 {
            appLogger.info(
                "Final QSO message transmitted — waiting for RX or courtesy timeout"
            )
        }
    }
}

