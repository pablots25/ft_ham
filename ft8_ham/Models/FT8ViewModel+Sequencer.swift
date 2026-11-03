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
        appLogger.info("Starting Sequencer Loop (\(digitalMode.displayName) - \(evenCycle ? "Even" : "Odd"))")
        isSequencerRunning = true
        PresenceManager.shared.sequencerDidStart(
            callsign: callsign, grid: locator,
            band: effectiveBand.rawValue, mode: digitalMode.logMode
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
            if self.digitalMode == .wspr {
                self.wsprCapture.start()
            } else {
                self.wsprCapture.stop()
            }
            
            // Ensure screen stays on
            self.updateScreenAlwaysOn()
            
            do {
                while !Task.isCancelled {
                    // 1. Calculate Next Slot Boundary
                    let now = AppClock.now()
                    let nextSlot = await self.slotManager.getNextSlot(from: now, mode: self.digitalMode)
                    
                    // 2. Wait for Boundary
                    try await self.slotManager.wait(until: nextSlot.startTime)
                    
                    // 3. WAKE UP - CRITICAL SECTION
                    try Task.checkCancellation()
                    
                    // --- HARVEST AND DECODE PREVIOUS SLOT ---
                    // The slot monitor has been analysing the audio as it
                    // arrived; take that spectrogram and start the next slot's
                    // in one step, so the new slot's block 0 sits on the boundary.
                    let completedSlotIndex = nextSlot.slotIndex - 1
                    let snapshot = self.slotMonitor.snapshotAndReset()
                    let harvestMode = self.digitalMode
                    // WSPR is decoded from the raw slot audio instead of the spectrogram.
                    let wsprSamples: [Float]? = harvestMode == .wspr
                        ? self.wsprCapture.harvest(nextSlotStart: nextSlot.startTime, now: AppClock.now())
                        : nil
                    let coveredSeconds = wsprSamples.map { Double($0.count) / self.wsprCapture.sampleRate }
                        ?? snapshot.duration

                    // FT8 needs ~12.6 s of signal, FT4 ~4.5 s, WSPR ~110.6 s.
                    let requiredSeconds = harvestMode.minimumDecodeDuration

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
                        let capturedLogger = self.rxLogger
                        let capturedSampleRate = self.wsprCapture.sampleRate
                        self.isHarvestingRX = true
                        Task.detached(priority: .userInitiated) { [weak self] in
                            let weakSelf = self
                            defer { Task { await MainActor.run { weakSelf?.isHarvestingRX = false } } }

                            let msgs: [[String: Any]]
                            if let wsprSamples {
                                msgs = capturedEngine.decodeAudioBuffer(
                                    WSPRCaptureBuffer.data(from: wsprSamples),
                                    sampleRate: capturedSampleRate,
                                    mode: harvestMode
                                )
                            } else {
                                msgs = capturedEngine.decodeWaterfallSnapshot(snapshot, mode: harvestMode)
                            }

                            capturedLogger.info("Decoded \(msgs.count) messages from slot \(completedSlotIndex)")
                            // WSPR spots have no waterfall labels, so no slot sequence.
                            await weakSelf?.handleDecodedMessages(
                                msgs,
                                slotIndex: completedSlotIndex,
                                slotSequence: wsprSamples == nil ? UInt(snapshot.slotSequence) : nil
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
            PresenceManager.shared.sequencerDidStop()
            self.isListening = false
            self.isTransmitting = false
            self.freeTextLoopActive = false
            self.sequencerTask = nil
            self.audioManager.stopPlayback()
            self.audioManager.stopMicInput()
            self.appLogger.info("Sequencer stopped clean.")
            AnalyticsManager.shared.stopRadioActivity()
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

    /// `true` when `lag` covers at least a whole slot (15 s FT8, 7.5 s FT4,
    /// 120 s WSPR). That only happens when the app was suspended
    /// and resumed, so it is logged as a warning instead of a Crashlytics non-fatal.
    nonisolated static func isSuspensionGap(lag: TimeInterval, mode: DigitalMode) -> Bool {
        lag >= mode.slotDuration
    }

    @MainActor
    internal func determineAction(for slot: SlotInfo) -> SequencerAction {
        if case .completed = qsoManager.qsoState {
            return .receive
        }
        
        let lag = AppClock.now().timeIntervalSince(slot.startTime)
        if lag > Self.maxSlotLag {
            if Self.isSuspensionGap(lag: lag, mode: slot.mode) {
                // A whole slot or more went by: the app was suspended (screen
                // lock, background) and just resumed. Expected, not a bug.
                appLogger.warning("Slot \(slot.slotIndex) skipped after resuming (\(lag)s late)")
            } else {
                appLogger.error("Severe system lag detected: \(lag)s. Skipping slot \(slot.slotIndex).")
            }
            return .skip
        }

        // Beacon modes (WSPR): no QSO state machine. When the beacon is on, transmit in a
        // random share of slots (WSJT-X style) so stations also hear each other.
        if !slot.mode.supportsQSO {
            guard self.transmitLoopActive else { return .receive }
            let percent = min(max(self.wsprTxPercent, 0), 100)
            if Int.random(in: 0..<100) < percent {
                appLogger.debug("Sequencer Decided: BEACON TX (Slot \(slot.slotIndex), \(percent)%)")
                return .transmit
            }
            return .receive
        }
        
        // Free text runs outside the QSO state machine: every my-turn slot.
        if self.freeTextLoopActive {
            return isMyTurn(slot) ? .transmit : .receive
        }

        // Check if we should transmit based on QSO state machine
        // Only TX when: calling CQ, in a "sending" state, or isReadyForTX (immediate response)
        let shouldTX = (self.transmitLoopActive && qsoManager.shouldTransmitThisSlot()) || self.isReadyForTX
        
        if shouldTX {
            if isMyTurn(slot) {
                // Clear isReadyForTX after using it to prevent repeated TX
                self.isReadyForTX = false
                appLogger.debug("Sequencer Decided: TRANSMIT (Slot \(slot.slotIndex), Even: \(slot.isEven))")
                return .transmit
            }
        }
        
        return .receive
    }
    
    /// Drops audio captured so far in this slot (e.g. after a band hop, so the
    /// next decode does not mix two bands).
    @MainActor
    internal func clearRXBuffer() {
        slotMonitor.resetSlot()
        wsprCapture.discardCurrentSlot()
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
        // Immediate replies only make sense in QSO modes.
        guard digitalMode.supportsQSO else { return }
        let now = AppClock.now()
        
        // 1. Obtener información del slot ACTUAL
        let currentSlot = await slotManager.getSlotInfo(
            at: now,
            mode: digitalMode
        )
        
        // 2. Calcular offset desde inicio del slot
        let offsetFromSlotStart = now.timeIntervalSince(currentSlot.startTime)
        
        let maxStartOffset = digitalMode.maxStartOffset
        
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
        
        let maxStartOffset = slot.mode.maxStartOffset
        
        
        // Slot-aware TX allowing late start within safe margin
        let waitStart = Date()
        
        if offsetFromSlotStart > maxStartOffset {
            txLogger.warning(
                "TX skipped for slot \(slot.slotIndex): start offset \(String(format: "%.2f", offsetFromSlotStart))s exceeds limit"
            )
            return
        }
        
        let signalEnd = slot.startTime.addingTimeInterval(
            slot.mode.minimumDecodeDuration
        )
        // The RX decode barrier exists so a QSO reply is chosen from the latest decodes.
        // Beacons do not depend on them, and WSPR decodes take seconds: do not wait.
        while slot.mode.supportsQSO && self.isHarvestingRX {
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
        let isFreeText = freeTextLoopActive && slot.mode.supportsQSO

        if !slot.mode.supportsQSO {
            // Beacon modes (WSPR) always send our own beacon message.
            let beacon = wsprBeaconMessage
            guard WSPRSupport.isValidMessage(beacon) else {
                audioError = "Invalid WSPR beacon message"
                txLogger.warning("Invalid WSPR beacon message: '\(beacon)'")
                return
            }
            guard let data = engine.generateAudio(
                beacon,
                frequency: Float(frequency),
                mode: slot.mode,
                toFile: nil
            ) else {
                txLogger.error("Failed to generate WSPR audio for: \(beacon)")
                return
            }
            txLogger.debug("WSPR beacon message: '\(beacon)'")
            message = beacon
            audioData = data
        } else if isFreeText {
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
            guard let data = engine.generateFreeText(text, frequency: Float(frequency), mode: slot.mode) else {
                txLogger.error("Failed to generate free text audio for: \(text)")
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

            guard let data = engine.generateAudio(
                message,
                frequency: Float(frequency),
                mode: slot.mode,
                toFile: nil
            ) else {
                txLogger.error("Failed to generate audio for: \(message)")
                return
            }
            audioData = data
        }

        let txMessage = FT8Message(
            text: message,
            mode: slot.mode,
            frequency: frequency,
            isTX: true,
            band: selectedBand
        )
        
        transmittedMessages.append(txMessage)
        txLogger.info("Added to TX list: \(message)")
        
        // Clear isReadyForTX after successful TX preparation
        self.isReadyForTX = false

        // Some modes start transmitting at a fixed point into the slot (WSPR: +1 s).
        let startDelay = slot.startTime
            .addingTimeInterval(slot.mode.transmissionStartDelay)
            .timeIntervalSinceNow
        if startDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
        }
        
        // The scenePhase handler stops the sequencer on backgrounding, but a TX
        // task already in flight can reach this point afterwards. Starting audio
        // in the background has no IO cycle and crashes AVAudioPlayerNode.
        guard UIApplication.shared.applicationState != .background else {
            txLogger.warning("TX skipped for slot \(slot.slotIndex): app is in background")
            return
        }

        AnalyticsManager.shared.startRadioActivity(.tx)
        sendCatFrequency(reason: "tx start")
        setCatPTT(true, reason: "tx start")
        audioManager.playAudio(audioData)
        InAppPrompts.shared.recordTXStarted()
        txLogger.info("TX Started: \(message)")
        txLogger.info(
            "TX starting \(String(format: "%.2f", Date().timeIntervalSince(slot.startTime)))s into slot \(slot.slotIndex)"
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

