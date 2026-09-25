//
//  Helpers.swift
//  ft_ham
//
//  Created by Pablo Turrion on 7/1/26.
//

import UIKit


extension FT8ViewModel{
    
    // MARK: - Helper Methods
    internal func extractWorkedLocators(from messages: [FT8Message]) {
        for msg in messages {
            if let dx = msg.locator, !dx.isEmpty, !workedLocatorsSet.contains(dx) {
                workedLocators.append(dx)
            }
        }
    }
    
    
    /// Adds the operator's own grid (from the map's location updates) once.
    func addUserLocator(_ locator: String) {
        guard !workedLocatorsSet.contains(locator) else { return }
        workedLocators.append(locator)
    }

    /// Appends the locators not yet known, in a single assignment so
    /// `workedLocators` publishes (and rebuilds its mirror Set) once.
    internal func addNewLocators(from newLocators: [String]) {
        var seen = workedLocatorsSet
        var additions: [String] = []
        for loc in newLocators where !seen.contains(loc) {
            seen.insert(loc)
            additions.append(loc)
        }
        guard !additions.isEmpty else { return }
        workedLocators.append(contentsOf: additions)
    }

    /// Replaces the displayed country pairs (deduplicated, order preserved),
    /// publishing only when the result differs from what is already shown.
    internal func setWorkedCountryPairs(_ pairs: [CountryPair]) {
        var seen = Set<CountryPair>()
        var unique: [CountryPair] = []
        for pair in pairs where !seen.contains(pair) {
            seen.insert(pair)
            unique.append(pair)
        }
        if unique != workedCountryPairs {
            workedCountryPairs = unique
        }
    }

    internal func extractWorkedCountryPairs(from messages: [FT8Message]) {
        for msg in messages {
            let pair = CountryPair(sender: msg.senderCountry, receiver: msg.dxCountry.country != nil ? msg.dxCountry : nil)
            if !workedCountryPairsSet.contains(pair) {
                workedCountryPairs.append(pair)
                workedCountryPairsSet.insert(pair)
            }
        }
    }

    internal func addNewCountryPairs(from newPairs: [CountryPair]) {
        var seen = workedCountryPairsSet
        var additions: [CountryPair] = []
        for pair in newPairs where !seen.contains(pair) {
            seen.insert(pair)
            additions.append(pair)
        }
        guard !additions.isEmpty else { return }
        workedCountryPairs.append(contentsOf: additions)
    }

    internal func hasConfirmedQSO(
        with callsign: String?,
        band: String,
        mode: String,
        matchBandModeOnly: Bool
    ) -> Bool {
        guard let callsign = callsign?.trimmingCharacters(in: .whitespacesAndNewlines),
              !callsign.isEmpty else {
            return false
        }

        // "Worked ever" is an O(1) Set lookup; only the band/mode-specific
        // variant needs to scan the log.
        if !matchBandModeOnly {
            return workedCallsigns.contains(callsign.uppercased())
        }

        return qsoList.contains { entry in
            guard entry.callsign.caseInsensitiveCompare(callsign) == .orderedSame else {
                return false
            }
            return entry.band == band && entry.mode == mode
        }
    }

    /// True when a callsign is not yet in the logbook (any band/mode).
    internal func isNewCallsign(_ callsign: String?) -> Bool {
        guard let callsign = callsign?.trimmingCharacters(in: .whitespacesAndNewlines),
              !callsign.isEmpty else {
            return false
        }
        return !workedCallsigns.contains(callsign.uppercased())
    }

    /// True when a decoded row should get the "new callsign" highlight: an
    /// incoming CQ from a station not yet worked, when the setting is enabled.
    internal func isNewCQCallsign(_ msg: FT8Message) -> Bool {
        guard highlightNewCallsigns, msg.msgType == .cq, !msg.isTX,
              let call = msg.callsign, !call.isEmpty else { return false }
        // Decoded callsigns are already uppercased and whitespace-free
        // (`FT8Message.splitParts`), so no per-row String allocations here.
        return !workedCallsigns.contains(call)
    }

    /// True when a decoded row should get the "calling you" highlight.
    internal func isCallingMeHighlighted(_ msg: FT8Message) -> Bool {
        highlightMyCallsign && CallAlertDetector.isCallingMe(msg, myCallsign: callsign)
    }

    /// The operator's watchlist, parsed once per change of the stored string.
    internal var watchList: WatchList {
        get {
            if watchListCache.storage != watchedCallsignsStorage {
                watchListCache = (watchedCallsignsStorage, WatchList(storage: watchedCallsignsStorage))
            }
            return watchListCache.list
        }
        set {
            objectWillChange.send()
            watchedCallsignsStorage = newValue.storage
        }
    }

    /// True when a received row was sent by a station on the watchlist.
    internal func isWatched(_ msg: FT8Message) -> Bool {
        guard !msg.isTX,
              msg.msgType != .internalTimestamp, msg.msgType != .unknown else { return false }
        return watchList.contains(msg.callsign)
    }

    /// The highlight for a decoded row. A call to us wins over a watched sender.
    internal func rowHighlight(for msg: FT8Message) -> RowHighlight {
        if isCallingMeHighlighted(msg) { return .callingMe }
        if isWatched(msg) { return .watched }
        return .none
    }

    /// Raises the enabled alerts at most once per slot:
    /// - a station calls us and no QSO was in progress at the start of the slot;
    /// - otherwise, a watched station is heard, at most once per station every
    ///   few minutes, and not while we are already working it.
    /// The sound is held back while we transmit so it cannot go on air.
    @MainActor
    internal func raiseAlerts(in messages: [FT8Message], qsoStateBeforeSlot: QSOState) {
        guard callAlertSound || callAlertHaptic || callAlertNotification else { return }

        let kind: CallAlertKind
        let message: FT8Message
        if let call = CallAlertDetector.alertMessage(
            in: messages, myCallsign: callsign, qsoState: qsoStateBeforeSlot
        ) {
            kind = .callingMe
            message = call
        } else if watchAlertEnabled, let watched = firstWatchedToAlert(in: messages) {
            kind = .watched
            message = watched
        } else {
            return
        }

        callAlerter.alert(
            kind,
            for: message,
            sound: callAlertSound && !isTransmitting,
            haptic: callAlertHaptic,
            notification: callAlertNotification
        )
    }

    /// The first watched station in the slot that is due an alert.
    private func firstWatchedToAlert(in messages: [FT8Message]) -> FT8Message? {
        guard !watchList.isEmpty else { return nil }
        let working = qsoManager.qsoState.lockedCallsign?.uppercased()
        let now = AppClock.now()
        for msg in messages where isWatched(msg) {
            guard let call = msg.callsign?.uppercased(), call != working else { continue }
            if watchAlertThrottle.shouldAlert(for: call, at: now) { return msg }
        }
        return nil
    }

    /// What a decoded station would still add to the logbook on the current
    /// band and mode: an unworked callsign, an unworked 4-char grid, an
    /// unworked country. Empty for our own TX rows and non-station rows.
    internal func neededStatus(for msg: FT8Message) -> NeededStatus {
        guard !msg.isTX,
              msg.msgType != .internalTimestamp, msg.msgType != .unknown,
              let call = msg.callsign, !call.isEmpty else { return [] }

        let band = effectiveBand.rawValue
        let mode = isFT4 ? "FT4" : "FT8"
        var status: NeededStatus = []

        if !workedIndex.callsignBandMode.contains(WorkedIndex.key(call, band: band, mode: mode)) {
            status.insert(.callsign)
        }
        if let locator = msg.locator, locator.count >= 4 {
            let grid4 = String(locator.prefix(4))
            if !workedIndex.gridBandMode.contains(WorkedIndex.key(grid4, band: band, mode: mode)) {
                status.insert(.grid)
            }
        }
        if let country = msg.senderCountry.country, !country.isEmpty,
           !workedIndex.countryBandMode.contains(WorkedIndex.key(country, band: band, mode: mode)) {
            status.insert(.dxcc)
        }
        return status
    }

    /// True when the row should survive the "Needed" decode filter.
    internal func isNeeded(_ msg: FT8Message) -> Bool {
        !neededStatus(for: msg).isEmpty
    }

    func generateMessages() -> [String] {
        let includeGrid = UserDefaults.standard.object(forKey: "cqIncludeGrid") as? Bool ?? true
        let currentParams = MessageParams(
            callsign: callsign,
            locator: locator,
            dxCallsign: dxCallsign,
            dxLocator: dxLocator,
            snrToSend: lastSentSNR,
            cqModifier: UserDefaults.standard.string(forKey: "cqModifier") ?? "NONE",
            cqIncludeGrid: includeGrid
        )
        
        appLogger.log(
            .info,
            "Generating messages for callsign: \(callsign), locator: \(locator), dxCallsign: \(dxCallsign), dxLocator: \(dxLocator), power: \(lastSentSNR), includeGrid: \(includeGrid)"
        )
        
        // Cache hit - avoid regeneration
        if let cached = cachedMessages, lastMessageParams == currentParams {
            return cached
        }
        
        // Generate and cache
        let messages = messageComposer.generateMessages(
            callsign: callsign,
            locator: locator,
            dxCallsign: dxCallsign,
            dxLocator: dxLocator,
            snrToSend: lastSentSNR,
            includeGrid: includeGrid
        )
        
        cachedMessages = messages
        lastMessageParams = currentParams
        return messages
    }
    
    
    // MARK: - Message Clearing
    @MainActor
    func clearReceived() {
        receivedMessages.removeAll()
        appLogger.log(.info, "Cleared all received messages")
    }
    
    @MainActor
    func clearTransmitted() {
        transmittedMessages.removeAll()
        resetQSOState()
        appLogger.log(.info, "Cleared all transmitted messages")
    }
    
    @MainActor
    func clearLastMessage() {
        decodedMessage = nil
        appLogger.log(.info, "Cleared last decoded message")
    }
    
    // MARK: - Screen Management
    @MainActor
    internal func updateScreenAlwaysOn() {
        appLogger.log(.debug, "isListening=\(isListening), isTransmitting=\(isTransmitting)")
        appLogger.log(.info, "Update ScreenAlwaysOn to \(isListening || isTransmitting)")
        UIApplication.shared.isIdleTimerDisabled = isListening || isTransmitting
    }

    // MARK: - QSO Frequency Alignment

    @MainActor
    internal func alignTXFrequencyForQSOStart(from message: FT8Message) {
        guard !holdTXFrequency else {
            appLogger.debug("holdTXFrequency enabled, keeping current TX frequency")
            return
        }

        guard !message.frequency.isNaN else {
            appLogger.warning("RX message has invalid frequency, TX frequency not updated")
            return
        }

        if frequency != message.frequency {
            appLogger.info(
                "Aligning TX frequency to RX message frequency: \(message.frequency) Hz"
            )
            frequency = message.frequency
        }
    }

}
