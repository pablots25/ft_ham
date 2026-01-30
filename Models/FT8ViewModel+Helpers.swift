//
//  Helpers.swift
//  ft8_ham
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
    
    
    internal func addNewLocators(from newLocators: [String]) {
        for loc in newLocators where !workedLocatorsSet.contains(loc) {
            workedLocators.append(loc)
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
        for pair in newPairs where !workedCountryPairsSet.contains(pair) {
            workedCountryPairs.append(pair)
            workedCountryPairsSet.insert(pair)
        }
    }

    func generateMessages() -> [String] {
        let currentParams = MessageParams(
            callsign: callsign,
            locator: locator,
            dxCallsign: dxCallsign,
            dxLocator: dxLocator,
            snrToSend: lastSentSNR
        )
        
        appLogger.log(
            .info,
            "Generating messages for callsign: \(callsign), locator: \(locator), dxCallsign: \(dxCallsign), dxLocator: \(dxLocator), power: \(lastSentSNR)"
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
            snrToSend: lastSentSNR
        )
        
        cachedMessages = messages
        lastMessageParams = currentParams
        return messages
    }
    
    
    // MARK: - Progress Bar Management
    func startProgressBarUTC() {
        progressTimerCancellable?.cancel()
        
        progressTimerCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                let calendar = Calendar.current
                let seconds = calendar.component(.second, from: now)
                let nanoseconds = calendar.component(.nanosecond, from: now)
                
                let cycleLength = isFT4 ? 7.5 : 15.0
                let totalSeconds = Double(seconds) + Double(nanoseconds) / 1_000_000_000
                let slotProgress = totalSeconds.truncatingRemainder(dividingBy: cycleLength) / cycleLength
                cycleProgress = slotProgress
            }
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
