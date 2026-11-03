//
//  FT8ViewModel+QSO.swift
//  ft_ham
//
//  Created by Pablo Turrion on 12/1/26.
//

import Foundation

extension FT8ViewModel {
    
    // MARK: - TX Message Indices

    /// Positions in `allMessages` (see `FT8MessageComposer.generateMessages`).
    enum TXMessageIndex {
        static let cq = 0
        static let grid = 1
        static let report = 2
        static let rReport = 3
        static let rrr = 4
        static let final73 = 5
        static let rr73 = 6
    }

    // MARK: - Reply Management

    /// Starts a QSO with the station that sent `message` because the operator
    /// tapped it. The QSO manager picks the first message to send (a grid for
    /// a CQ, a report when the station already sent me its grid), and the
    /// result goes through the same path the automatic sequencer uses.
    ///
    /// Does not change `autoSequencingEnabled`, which is a user setting.
    @MainActor
    func reply(to message: FT8Message) {
        let dxCall = message.callsign?.uppercased() ?? ""
        appLogger.info("Initializing reply to \(dxCall.isEmpty ? "unknown" : dxCall)")

        // Same safety checks the automatic path applies before starting a QSO.
        guard settingsLoaded else {
            appLogger.warning("Reply to \(dxCall) ignored: station callsign or locator not configured")
            return
        }
        guard isValidCallsign(dxCall) else {
            appLogger.warning("Reply ignored: invalid callsign '\(dxCall)'")
            return
        }

        // Tapping the station we are already working (common in pileups)
        // should not pop a toast every time.
        let isAlreadyLockedDX = qsoManager.lockedDXCallsign.caseInsensitiveCompare(dxCall) == .orderedSame

        qsoManager.currentMode = digitalMode
        qsoManager.currentBand = effectiveBand
        qsoManager.currentCustomFrequencyHz = selectedBand == .custom ? customDialFrequencyHz : nil

        let action = qsoManager.startReply(to: message, myCallsign: callsign, myLocator: locator)
        guard action != .ignore else {
            appLogger.info("Reply to \(dxCall) ignored by the QSO manager")
            return
        }

        handleRXAction(action, operatorMessage: message)

        if !isAlreadyLockedDX {
            toast = .info(
                String(
                    localized: "Replying to \(dxCall)",
                    comment: "Toast shown when the operator taps a station to reply. The argument is the other station's callsign."
                )
            )
        }

        appLogger.log(
            .info,
            "QSO sequence started: state=\(qsoManager.qsoState), messageIndex=\(selectedMessageIndex ?? -1), evenCycle=\(evenCycle)"
        )
    }

    // MARK: - QSO Start

    /// Points TX at the DX station and gets the transmit loop going.
    ///
    /// Frequency and slot both come from the same DX message, so we answer on
    /// the station's frequency in the opposite cycle. Shared by `reply(to:)`
    /// and every sending case of `handleRXAction(_:operatorMessage:)`.
    ///
    /// - Parameters:
    ///   - message: The DX station's message. When nil, the current frequency
    ///     and slot are kept.
    ///   - messageIndex: The `allMessages` entry to send (`TXMessageIndex`).
    ///   - alignFrequency: Move the TX frequency to the DX message frequency.
    ///   - reason: Logged when the pending TX is invalidated.
    @MainActor
    internal func startQSO(
        from message: FT8Message?,
        messageIndex: Int,
        alignFrequency: Bool,
        reason: String
    ) {
        if let message {
            if alignFrequency {
                alignTXFrequencyForQSOStart(from: message)
            }
            alignTXSlot(toOppositeOf: message)
        }

        invalidatePendingTX(reason: reason)
        selectedMessageIndex = messageIndex
        allMessages = generateMessages()

        if !transmitLoopActive {
            appLogger.info("Starting TX loop...")
            toggleTransmit()
        }
        isReadyForTX = true

        Task { @MainActor in
            await tryImmediateTXIfPossible()
        }
    }

    /// Transmit in the cycle opposite to the one `message` was received in.
    @MainActor
    internal func alignTXSlot(toOppositeOf message: FT8Message) {
        txSlotPreference = (message.cycle == .even) ? .forceOdd : .forceEven
        evenCycle = (message.cycle == .odd)
    }

    /// The most recent decode sent by `callsign` (case-insensitive).
    @MainActor
    internal func lastDecodedMessage(from callsign: String) -> FT8Message? {
        guard !callsign.isEmpty else { return nil }
        return receivedMessages.last { msg in
            !msg.isTX && msg.msgType != .internalTimestamp &&
            msg.callsign?.caseInsensitiveCompare(callsign) == .orderedSame
        }
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
