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
        
        // The monitor hands every analysed row to the waterfall on this same
        // queue; the waterfall copies it and hops to @MainActor itself.
        let waterfallVM = self.waterfallVM
        slotMonitor.rowHandler = { row, count, firstBinHz, binHz, slotSequence, slotRow in
            waterfallVM.appendMonitorRow(
                UnsafeBufferPointer(start: row, count: Int(count)),
                firstBinHz: firstBinHz,
                binHz: binHz,
                slotSequence: slotSequence,
                slotRow: Int(slotRow)
            )
        }

        // A serial queue: the global concurrent queue can run two consecutive
        // buffers on two threads, and audio fed to the monitor out of order
        // corrupts both the display and the decode.
        let monitorQueue = DispatchQueue(label: "ft8.slotMonitor", qos: .userInitiated)
        audioManager.audioSamplesPublisher
            .receive(on: monitorQueue)
            .sink { [weak self] samples in
                guard let self else { return }
                // One FFT pass serves both the waterfall (rows as they are
                // analysed) and the decoder (snapshot at the slot boundary).
                samples.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    self.slotMonitor.feedSamples(base, count: UInt(buffer.count))
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
    
    // MARK: - Audio Errors

    /// Surfaces audio engine errors, and any other `audioError` the view model
    /// records, as a warning toast. The same message shows at most once every
    /// 10 seconds. Runs in unit tests too, since it touches no audio hardware.
    @MainActor
    internal func setupAudioErrorSubscription() {
        audioManager.audioErrorPublisher
            .sink { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.audioError = message
                }
            }
            .store(in: &cancellables)

        $audioError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.showAudioErrorToast(message, at: Date())
            }
            .store(in: &cancellables)
    }

    /// Shows `message` as a warning toast unless it was shown within the
    /// throttle interval.
    @MainActor
    internal func showAudioErrorToast(_ message: String, at now: Date) {
        guard audioErrorToastThrottle.shouldShow(message, at: now) else { return }
        appLogger.warning("Audio error shown to the user: \(message)")
        toast = .warning(message)
    }

    // MARK: - Optimized RX Decode Handling
    // Called from setupAudioSubscriptions when a buffer is ready
    @MainActor
    internal func handleDecodedMessages(_ decodedAny: [Any], slotIndex: Int?, slotSequence: UInt? = nil) async {
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
        
        await self.applyBatchUpdates(result, slotIndex: slotIndex, slotSequence: slotSequence)
    }
    
    // MARK: - Apply Batch Updates
    @MainActor
    /// - Parameter slotSequence: the monitor slot the batch was decoded from,
    ///   which places the waterfall labels on their signals.
    internal func applyBatchUpdates(_ result: BatchProcessResult, slotIndex: Int?, slotSequence: UInt? = nil) async {
        let performanceLog = OSLog(subsystem: "com.ft8ham.app", category: "Performance")
        os_signpost(.begin, log: performanceLog, name: "UI Update")
        defer { os_signpost(.end, log: performanceLog, name: "UI Update") }
        
        // Reset response tracking for this slot before processing messages
        qsoManager.prepareForRXSlot()
        // Keep the mode/band context current so setupNewQSO snapshots the right
        // values even if the user switches mode/band mid-QSO.
        qsoManager.isFT4Mode = isFT4
        qsoManager.currentBand = effectiveBand
        qsoManager.currentCustomFrequencyHz = selectedBand == .custom ? customDialFrequencyHz : nil
        
        // Track if this slot contained our TX - if so, we shouldn't expect a response yet
        let slotContainedOurTX = result.messages.contains { $0.isTX } ||
        (slotIndex != nil && lastTransmittedSlotIndex == slotIndex)
        
        // Publish the decoded rows once per slot (one objectWillChange), not
        // once per message, and keep the list bounded.
        let showSelfTX = decodeSelfTXMessages
        let newRows = result.messages.filter { !$0.isTX || showSelfTX }
        if !newRows.isEmpty {
            var updated = receivedMessages
            updated.append(contentsOf: newRows)
            let overflow = updated.count - Constants.maxReceivedMessages
            if overflow > 0 { updated.removeFirst(overflow) }
            receivedMessages = updated
        }

        // While we are calling CQ, several stations may answer in the same
        // slot. Pick one at random (optionally favouring never-worked calls)
        // instead of whichever the decoder happened to list first; the QSO
        // manager locks onto the first caller it sees and ignores the rest.
        var orderedMessages = result.messages
        if pileupRandomCaller, qsoManager.qsoState == .callingCQ, transmitLoopActive {
            var selector = PileupSelector(preferNeverWorked: pileupPreferNewCallsigns)
            let pick = selector.prioritize(
                result.messages, myCallsign: callsign, workedCallsigns: workedCallsigns
            )
            if pick.pileupSize > 1, let chosen = pick.chosen {
                orderedMessages = pick.messages
                appLogger.info("Pile-up of \(pick.pileupSize) callers, picked \(chosen.callsign ?? "?")")
            }
        }

        // Read before the loop: answering our CQ moves the QSO manager out of
        // `.callingCQ`, which would otherwise suppress the alert for that call.
        let qsoStateBeforeSlot = qsoManager.qsoState

        for message in orderedMessages {
            if message.isTX {
                continue
            } else if message.msgType != .internalTimestamp && message.msgType != .unknown {
                let shouldAutoReplyToCQ = autoCQReplyEnabled && !isWorked(
                    message.callsign,
                    scope: autoCQReplyOnlyNewBandMode ? .currentBandAndMode : .anyBand
                )
                let effectiveAutoCQReplyEnabled = (message.msgType == .cq)
                ? shouldAutoReplyToCQ
                : autoCQReplyEnabled

                let action = qsoManager.handleIncomingMessage(
                    message,
                    myCallsign: callsign,
                    autoSequencingEnabled: autoSequencingEnabled,
                    autoCQReplyEnabled: effectiveAutoCQReplyEnabled
                )
                
                handleRXAction(action)
            }
        }
        
        raiseAlerts(in: result.messages, qsoStateBeforeSlot: qsoStateBeforeSlot)

        // After processing all messages in the slot, check for timeout
        // Only trigger timeout if this was an RX slot (not our TX slot)
        // DX's response will come in the slot AFTER we transmit
        if !slotContainedOurTX {
            // Sync the user-configured retry limit into the manager before each check
            qsoManager.maxRetrySlots = maxRetrySlots
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
        
        // Mark stations already in the log, then place the labels on the
        // rows their signals occupy.
        let labels = result.labels.map { label -> WaterfallLabel in
            var l = label
            l.isWorked = isWorked(label.callsign, scope: .anyBand)
            return l
        }
        waterfallVM.addLabels(
            labels,
            slotSequence: slotSequence,
            signalDuration: isFT4 ? Constants.ft4SignalDuration : Constants.ft8SignalDuration
        )
        
        // Note: `result.waterfallSamples` is never populated by the engine (no
        // "audioSamples" key), and `updateWaterfall(from:)` expects FFT
        // magnitudes, not samples — so that path was dead and is gone.

        if !result.newLocators.isEmpty {
            addNewLocators(from: result.newLocators)
        }
        
        // The map shows the country pairs of the current slot. Replace the
        // array in one assignment (one publish) instead of removeAll + N appends
        // (N+1 publishes and an O(n²) Set rebuild through `didSet`).
        setWorkedCountryPairs(result.workedCountries)
        
        if result.shouldResetFirstLoop {
            firstLoopRX = false
        }
        
        // PSK Reporter integration: Report decoded RX messages
        if pskReporterEnabled {
            reportToPSKReporterIfNeeded(from: result.messages)
        }
    }
    
    // MARK: - PSK Reporter Integration
    private func reportToPSKReporterIfNeeded(from messages: [FT8Message]) {
        guard !callsign.isEmpty else {
            rxLogger.debug("PSK Reporter: Skipping (no callsign configured)")
            return
        }
        
        let reportableMessages = messages.filter { !$0.isTX && $0.msgType != .internalTimestamp && $0.callsign != nil }
        guard !reportableMessages.isEmpty else {
            rxLogger.debug("PSK Reporter: No reportable messages in batch")
            return
        }
        
        rxLogger.info("PSK Reporter: Processing \(reportableMessages.count) messages for upload")
        
        for message in reportableMessages {
            guard let senderCallsign = message.callsign, !senderCallsign.isEmpty else { continue }
            
            let frequencyHz = selectedBand.frequency(for: isFT4 ? .ft4 : .ft8) ?? 0
            let offsetHz = UInt64(message.frequency)
            let totalFreq = UInt64(frequencyHz) + offsetHz
            
            let mode: PSKReporterMode = isFT4 ? .ft4 : .ft8
            let report = PSKReporterReport(
                receiverCallsign: callsign,
                senderCallsign: senderCallsign,
                receiverLocator: locator,
                frequencyHz: totalFreq,
                mode: mode,
                snr: Int(message.measuredSNR.rounded())
            )
            
//            rxLogger.debug("PSK Reporter: Submitting \(senderCallsign) on \(band) @ \(totalFreq) Hz, SNR \(Int(message.measuredSNR.rounded()))")
            PremiumFeatures.pskReporter.report(report, testMode: false)
        }
        
        rxLogger.info("PSK Reporter: Submitted \(reportableMessages.count) reports")
    }
    
    /// Applies a QSO state-machine action.
    ///
    /// - Parameters:
    ///   - action: What the QSO manager decided to do next.
    ///   - operatorMessage: The message the operator tapped to reply to, when
    ///     the action comes from `reply(to:)`. On the automatic path it is nil
    ///     and the DX station's most recent decode is used instead.
    @MainActor
    internal func handleRXAction(_ action: QSOAction, operatorMessage: FT8Message? = nil) {
        // The operator picked a station, so always move to its frequency. On
        // the automatic path only a new grid exchange moves the TX frequency,
        // mid-QSO steps keep it where it is.
        let operatorStarted = operatorMessage != nil

        switch action {
        case .sendGrid(let dxCall, let dxLoc):
            appLogger.info("Applying action: sendGrid for \(dxCall)")
            dxCallsign = dxCall
            dxLocator = dxLoc
            startQSO(
                from: operatorMessage ?? lastDecodedMessage(from: dxCall),
                messageIndex: TXMessageIndex.grid,
                alignFrequency: true,
                reason: "RX action: sendGrid"
            )

        case .sendReport(let dxCall, _):
            appLogger.info("Applying action: sendReport for \(dxCall)")
            startQSO(
                from: operatorMessage ?? lastDecodedMessage(from: dxCall),
                messageIndex: TXMessageIndex.report,
                alignFrequency: operatorStarted,
                reason: "RX action: sendReport"
            )

        case .sendRReport(let dxCall, _):
            appLogger.info("Applying action: sendRReport for \(dxCall)")
            startQSO(
                from: operatorMessage ?? lastDecodedMessage(from: dxCall),
                messageIndex: TXMessageIndex.rReport,
                alignFrequency: operatorStarted,
                reason: "RX action: sendRReport"
            )

        case .sendRRR(let dxCall):
            appLogger.info("Applying action: sendRRR for \(dxCall)")
            startQSO(
                from: operatorMessage ?? lastDecodedMessage(from: dxCall),
                messageIndex: TXMessageIndex.rrr,
                alignFrequency: operatorStarted,
                reason: "RX action: sendRRR"
            )

        case .sendRR73(let dxCall):
            appLogger.info("Applying action: sendRR73 for \(dxCall)")
            dxCallsign = dxCall
            startQSO(
                from: operatorMessage ?? lastDecodedMessage(from: dxCall),
                messageIndex: TXMessageIndex.rr73,
                alignFrequency: operatorStarted,
                reason: "RX action: sendRR73"
            )

        case .send73(let dxCall):
            appLogger.info("Applying action: send73 for \(dxCall)")
            dxCallsign = dxCall
            startQSO(
                from: operatorMessage ?? lastDecodedMessage(from: dxCall),
                messageIndex: TXMessageIndex.final73,
                alignFrequency: operatorStarted,
                reason: "RX action: send73"
            )

        case .completeQSO:
            appLogger.info("Applying action: completeQSO for \(dxCallsign)")

            invalidatePendingTX(reason: "QSO completed")

            let completedCallsign = dxCallsign.isEmpty
            ? (qsoManager.lastCompletedDXCallsign ?? "")
            : dxCallsign
            let completedLocator = dxLocator.isEmpty
            ? (qsoManager.lastCompletedDXLocator ?? "")
            : dxLocator
            
            let logEntry = qsoManager.createLogEntry(
                dxCallsign: completedCallsign,
                dxLocator: completedLocator,
                qsoDate: AppClock.now(),
                band: qsoManager.qsoStartBand ?? effectiveBand,
                isFT4: qsoManager.qsoStartedAsFT4,
                rstSent: qsoManager.lastSentSNR,
                rstRcvd: qsoManager.lastReceivedSNR,
                customFrequencyHz: qsoManager.qsoStartBand != nil
                    ? qsoManager.qsoStartCustomFrequencyHz
                    : (selectedBand == .custom ? customDialFrequencyHz : nil)
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


        case .offerLogQSO:
            appLogger.info("Applying action: offerLogQSO for \(dxCallsign)")

            invalidatePendingTX(reason: "QSO timed out with reports exchanged")

            let completedCallsign = dxCallsign.isEmpty
            ? (qsoManager.lastCompletedDXCallsign ?? "")
            : dxCallsign
            let completedLocator = dxLocator.isEmpty
            ? (qsoManager.lastCompletedDXLocator ?? "")
            : dxLocator

            let logEntry = qsoManager.createLogEntry(
                dxCallsign: completedCallsign,
                dxLocator: completedLocator,
                qsoDate: AppClock.now(),
                band: qsoManager.qsoStartBand ?? effectiveBand,
                isFT4: qsoManager.qsoStartedAsFT4,
                rstSent: qsoManager.lastSentSNR,
                rstRcvd: qsoManager.lastReceivedSNR,
                customFrequencyHz: qsoManager.qsoStartBand != nil
                    ? qsoManager.qsoStartCustomFrequencyHz
                    : (selectedBand == .custom ? customDialFrequencyHz : nil)
            )

            // Clear DX info and return to CQ before showing the prompt.
            dxCallsign = ""
            dxLocator = ""
            selectedMessageIndex = 0
            resetQSOState()

            // An unconfirmed contact is never auto-logged: always ask, even when
            // autoQSOLogging is on, so the operator can vet the doubtful QSO.
            offerLogging(qso: logEntry, unconfirmed: true)


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

            // Track first-run milestone
            if !UserDefaults.standard.bool(forKey: "hasSeenFirstDecode") {
                UserDefaults.standard.set(true, forKey: "hasSeenFirstDecode")
            }
            
            extractWorkedLocators(from: [message])
            
            rxLogger.log(
                .info,
                "Decoded: '\(text)' SNR: \(message.measuredSNR) Freq: \(message.frequency) Time: \(message.timeOffset)"
            )
        }
        
        decodedMessage = receivedMessages.last
    }
    
    
}
