//
//  FT8ViewModel+Audio.swift
//  ft_ham
//
//  Created by Pablo Turrion on 12/1/26.
//

import Foundation
import Accelerate
import Combine
import os.signpost

extension FT8ViewModel {
    
    // MARK: - Audio Subscriptions (Optimized)
    
    internal func setupAudioSubscriptions() {
        if isRunningTests {
            return
        }
        
        audioManager.audioSamplesPublisher
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] samples in
                guard let self else { return }
                
                // Append to buffer for decoding
                let data = samples.withUnsafeBytes { Data($0) }
                self.rxBufferLock.lock()
                self.rxSampleBuffer.append(data)
                self.rxBufferLock.unlock()
                
                // Waterfall is independent
                Task { @MainActor in
                    self.waterfallVM.updateWaterfallFromSamples(samples)
                }
            }
            .store(in: &cancellables)

        audioManager.txStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self else { return }

                // TX just finished
                if !isPlaying {
                    self.handleTXDidFinishFromAudioManager()
                }
            }
            .store(in: &cancellables)

    }
    
    // MARK: - Optimized RX Decode Handling
    // Called from setupAudioSubscriptions when a buffer is ready
    @MainActor
    internal func handleDecodedMessages(_ decodedAny: [Any], slotIndex: Int?) async {
        let batch = decodedAny as? [[String: Any]] ?? []
        rxLogger.debug("handleDecodedMessages: processing batch of \(batch.count)")
        
        let result = await messageProcessor.process(
            batch,
            isFT4: isFT4,
            selectedBand: selectedBand,
            firstLoopRX: firstLoopRX,
            isTX: false,
            txMessage: transmittedMessages.last ?? FT8Message.empty(),
            existingLocators: workedLocatorsSet,
            decodeSelfTXMessages: decodeSelfTXMessages
        )
        
        await self.applyBatchUpdates(result, slotIndex: slotIndex)
    }
    
    // MARK: - Apply Batch Updates
    @MainActor
    internal func applyBatchUpdates(_ result: BatchProcessResult, slotIndex: Int?) async {
        let performanceLog = OSLog(subsystem: "com.ft8ham.app", category: "Performance")
        os_signpost(.begin, log: performanceLog, name: "UI Update")
        defer { os_signpost(.end, log: performanceLog, name: "UI Update") }
        
        // Reset response tracking for this slot before processing messages
        qsoManager.prepareForRXSlot()
        
        // Track if this slot contained our TX - if so, we shouldn't expect a response yet
        let slotContainedOurTX = result.messages.contains { $0.isTX } ||
        (slotIndex != nil && lastTransmittedSlotIndex == slotIndex)
        
        for message in result.messages {
            if !message.isTX {
                receivedMessages.append(message)
            } else if self.decodeSelfTXMessages {
                receivedMessages.append(message)
            }
            
            if message.isTX {
                continue
            } else if message.msgType != .internalTimestamp && message.msgType != .unknown {
                let action = qsoManager.handleIncomingMessage(
                    message,
                    myCallsign: callsign,
                    autoSequencingEnabled: autoSequencingEnabled,
                    autoCQReplyEnabled: autoCQReplyEnabled
                )
                
                handleRXAction(action)
            }
        }
        
        // After processing all messages in the slot, check for timeout
        // Only trigger timeout if this was an RX slot (not our TX slot)
        // DX's response will come in the slot AFTER we transmit
        if !slotContainedOurTX {
            let timeoutAction = qsoManager.handleQSOTimeout()
            if timeoutAction != .ignore {
                handleRXAction(timeoutAction)
            }
        }
        
        if let lastMessage = result.messages.last(where: { $0.msgType != .internalTimestamp }) {
            decodedMessage = lastMessage
        }

        let decodedCount = result.messages.filter {
            $0.msgType != .internalTimestamp && !$0.isTX
        }.count
        if decodedCount > 0 {
            AnalyticsManager.shared.addDecodedMessages(count: decodedCount)
        }
        
        waterfallVM.addVerticalLabels(result.labels)
        
        if !result.waterfallSamples.isEmpty {
            waterfallVM.updateWaterfall(from: result.waterfallSamples)
        }
        
        if !result.newLocators.isEmpty {
            addNewLocators(from: result.newLocators)
        }
        
        workedCountryPairs.removeAll()
        workedCountryPairsSet.removeAll()
        addNewCountryPairs(from: result.workedCountries)
        
        if result.shouldResetFirstLoop {
            firstLoopRX = false
        }
    }
    
    @MainActor
    internal func handleRXAction(_ action: QSOAction) {
        switch action {
        case .sendGrid(let dxCall, let dxLoc):
            appLogger.info("Applying action: sendGrid for \(dxCall)")
            
            if let rxMessage = receivedMessages.last(
                where: { !$0.isTX && $0.callsign == dxCall }
            ) {
                alignTXFrequencyForQSOStart(from: rxMessage)
            }
            
            invalidatePendingTX(reason: "RX action: sendGrid")
            dxCallsign = dxCall
            dxLocator = dxLoc
            selectedMessageIndex = 1
            
            // Align TX slot with RX (FT8 canonical)
            if let last = receivedMessages.last(where: { !$0.isTX && $0.msgType != .internalTimestamp }) {
                txSlotPreference = (last.cycle == .even) ? .forceOdd : .forceEven
                evenCycle = (last.cycle == .odd)
            }
            
            if !transmitLoopActive {
                appLogger.info("Restarting TX loop...")
                toggleTransmit()
            }
            isReadyForTX = true
            Task { @MainActor in
                await tryImmediateTXIfPossible()
            }
            
        case .sendReport(let dxCall, let report):
            appLogger.info("Applying action: sendReport for \(dxCall)")
            invalidatePendingTX(reason: "RX action: sendReport")
            selectedMessageIndex = 2
            
            if let last = receivedMessages.last(where: { !$0.isTX && $0.msgType != .internalTimestamp }) {
                txSlotPreference = (last.cycle == .even) ? .forceOdd : .forceEven
                evenCycle = (last.cycle == .odd)
            }
            
            if !transmitLoopActive {
                appLogger.info("Restarting TX loop...")
                toggleTransmit()
            }
            isReadyForTX = true
            Task { @MainActor in
                await tryImmediateTXIfPossible()
            }
            
        case .sendRReport(let dxCall, let report):
            appLogger.info("Applying action: sendRReport for \(dxCall)")
            invalidatePendingTX(reason: "RX action: sendRReport")
            selectedMessageIndex = 3
            
            if let last = receivedMessages.last(where: { !$0.isTX && $0.msgType != .internalTimestamp }) {
                txSlotPreference = (last.cycle == .even) ? .forceOdd : .forceEven
                evenCycle = (last.cycle == .odd)
            }
            
            if !transmitLoopActive {
                appLogger.info("Restarting TX loop...")
                toggleTransmit()
            }
            isReadyForTX = true
            Task { @MainActor in
                await tryImmediateTXIfPossible()
            }
            
        case .sendRRR:
            appLogger.info("Applying action: sendRRR for \(dxCallsign)")
            invalidatePendingTX(reason: "RX action: sendRRR")
            selectedMessageIndex = 4
            if !transmitLoopActive {
                appLogger.info("Restarting TX loop...")
                toggleTransmit()
            }
            isReadyForTX = true
            Task { @MainActor in
                await tryImmediateTXIfPossible()
            }
            
        case .sendRR73(let dxCall):
            appLogger.info("Applying action: sendRR73 for \(dxCall)")
            dxCallsign = dxCall
            allMessages = generateMessages()
            selectedMessageIndex = 6
            invalidatePendingTX(reason: "RX action: sendRR73")
            if !transmitLoopActive {
                appLogger.info("Restarting TX loop...")
                toggleTransmit()
            }
            isReadyForTX = true
            Task { @MainActor in
                await tryImmediateTXIfPossible()
            }
            
        case .send73(let dxCall):
            appLogger.info("Applying action: send73 for \(dxCall)")
            dxCallsign = dxCall
            allMessages = generateMessages()
            selectedMessageIndex = 5
            invalidatePendingTX(reason: "RX action: send73")
            if !transmitLoopActive {
                appLogger.info("Restarting TX loop...")
                toggleTransmit()
            }
            isReadyForTX = true
            Task { @MainActor in
                await tryImmediateTXIfPossible()
            }
            
        case .completeQSO:
            appLogger.info("Applying action: completeQSO for \(dxCallsign)")

            invalidatePendingTX(reason: "QSO completed")
            
            let logEntry = qsoManager.createLogEntry(
                dxCallsign: dxCallsign,
                dxLocator: dxLocator,
                qsoDate: .now,
                frequency: frequency,
                band: selectedBand,
                isFT4: isFT4,
                rstSent: qsoManager.lastSentSNR,
                rstRcvd: qsoManager.lastReceivedSNR
            )

            qsoManager.resetRadioStateAfterCompletion()

            // Clear DX info and return to CQ
            dxCallsign = ""
            dxLocator = ""
            selectedMessageIndex = 0
            
            // Resume calling CQ if TX loop is active
            if transmitLoopActive {
                qsoManager.startCallingCQ()
                isReadyForTX = true
            }

            handleQSOLogging(qso: logEntry)


        case .abortQSO:
            appLogger.warning("QSO aborted for \(dxCallsign)")
            invalidatePendingTX(reason: "RX action: abortQSO")
            dxCallsign = ""
            dxLocator = ""
            selectedMessageIndex = 0
            resetQSOState()
            
            // Resume calling CQ if TX loop is active
            if transmitLoopActive {
                qsoManager.startCallingCQ()
                isReadyForTX = true
            }
            
        case .sendCQ:
            appLogger.info("Applying action: sendCQ")
            dxCallsign = ""
            selectedMessageIndex = 0
            if !transmitLoopActive {
                appLogger.info("Restarting TX loop...")
                toggleTransmit()
            }
            isReadyForTX = true
            
        case .ignore:
            break
        default:
            break
        }
    }
    
    
    // MARK: - WAV Decoding
    @MainActor
    func decodeFromWav() {
        let decodedAny: [[AnyHashable: Any]] = wavURL.map {
            engine.decode($0, isFT4: isFT4)
        } ?? engine.decode(nil, isFT4: isFT4)
        
        rxLogger.log(.info, "Decoding messages from \(wavURL?.lastPathComponent ?? "default source")")
        
        let decodedDicts: [[String: Any]] = decodedAny.compactMap { dict in
            var stringDict: [String: Any] = [:]
            for (key, value) in dict {
                if let keyStr = key as? String {
                    stringDict[keyStr] = value
                }
            }
            return stringDict
        }
        
        for dict in decodedDicts {
            guard let text = dict["text"] as? String else { continue }
            // -99 is a decoder sentinel meaning "could not compute SNR", treat as NaN
            let rawSnr = (dict["snr"] as? Double) ?? (dict["snr_db"] as? Double) ?? .nan
            let snr = (rawSnr <= -99) ? .nan : rawSnr
            let freq = dict["frequency"] as? Double ?? .nan
            let timeOffset = (dict["timeDelta"] as? Double) ?? (dict["time"] as? Double) ?? .nan
            let ldpc = (dict["ldpcErrors"] as? Int) ?? (dict["ldpc_errors"] as? Int) ?? 0
            
            let message = FT8Message(
                text: text,
                mode: isFT4 ? .ft4 : .ft8,
                isRealtime: false,
                timestamp: .now,
                measuredSNR: snr,
                frequency: freq,
                timeOffset: timeOffset,
                ldpcErrors: ldpc,
                isTX: false,
                band: selectedBand
            )
            
            receivedMessages.append(message)
            
            extractWorkedLocators(from: [message])
            
            rxLogger.log(
                .info,
                "Decoded: '\(text)' SNR: \(message.measuredSNR) Freq: \(message.frequency) Time: \(message.timeOffset)"
            )
        }
        
        decodedMessage = receivedMessages.last
    }
    
    
}
