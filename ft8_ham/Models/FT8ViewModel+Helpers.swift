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
