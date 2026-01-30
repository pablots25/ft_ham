//
//  MessageProcessor.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 1/1/26.
//
import os.signpost

private let performanceLog = OSLog(subsystem: "com.ft8ham.app", category: "Performance")

internal struct BatchProcessResult {
    let messages: [FT8Message]
    let labels: [(String, Double)]
    let waterfallSamples: [Float]
    let newLocators: [String]
    let workedCountries: [CountryPair]
    let shouldResetFirstLoop: Bool
}

// MARK: - MessageParams
struct MessageParams: Equatable {
    let callsign: String
    let locator: String
    let dxCallsign: String
    let dxLocator: String
    let snrToSend: Double

    static func ==(lhs: MessageParams, rhs: MessageParams) -> Bool {
        return lhs.callsign == rhs.callsign &&
               lhs.locator == rhs.locator &&
               lhs.dxCallsign == rhs.dxCallsign &&
               lhs.dxLocator == rhs.dxLocator &&
               (lhs.snrToSend.isNaN && rhs.snrToSend.isNaN || lhs.snrToSend == rhs.snrToSend)
    }
}

// MARK: - Message Processor Actor
actor MessageProcessor {
    private let appLogger = AppLogger(category: "MSGPROC")
    
    func process(
        _ batch: [[String: Any]],
        isFT4: Bool,
        selectedBand: FT8Message.Band,
        firstLoopRX: Bool,
        isTX: Bool,
        txMessage: FT8Message,
        existingLocators: Set<String>,
        decodeSelfTXMessages: Bool
    ) -> BatchProcessResult {
        
        appLogger.log(.info, "Starting batch processing: \(batch.count) messages")
        os_signpost(.begin, log: performanceLog, name: "Batch Processing")
        defer {
            os_signpost(.end, log: performanceLog, name: "Batch Processing")
        }
        
        var messagesToAdd: [FT8Message] = []
        messagesToAdd.reserveCapacity(batch.count + 1)
        
        var labelsToAdd: [(String, Double)] = []
        labelsToAdd.reserveCapacity(batch.count)
        
        var waterfallSamples: [Float] = []
        var newLocators: [String] = []
        var newCountryPairs: [CountryPair] = []
        var shouldResetFirstLoop = false
        
        // Add timestamp marker
        let now = Date()
        let slotDuration: Double = isFT4 ? 7.5 : 15.0
        let roundedTimestamp = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / (slotDuration / 2.0)) * (slotDuration / 2.0))
        
        messagesToAdd.append(
            FT8Message(
                text: "\(DateFormatter.utcFormatterMessage.string(from: roundedTimestamp)) - \(selectedBand.rawValue)",
                mode: isFT4 ? .ft4 : .ft8,
                timestamp: roundedTimestamp,
                band: selectedBand,
                msgType: FT8MessageType.internalTimestamp
            )
        )
        
        for msgDict in batch {
            guard let text = msgDict["text"] as? String else { continue }
            
            // Handle partial slot messages
            if text == "Partial slot" && firstLoopRX {
                messagesToAdd.append(
                    FT8Message(
                        text: "Partial data loss",
                        mode: isFT4 ? .ft4 : .ft8,
                        measuredSNR: .nan,
                        frequency: .nan,
                        timeOffset: .nan,
                        isTX: false,
                        band: selectedBand,
                        allowsReply: false
                    )
                )
                shouldResetFirstLoop = true
                continue
            }
            
            let message = MessageProcessor.createMessage(
                from: msgDict,
                isFT4: isFT4,
                selectedBand: selectedBand,
                isTX: isSelfTXMessage(
                    text: text,
                    txMessage: txMessage.text
                )
            )
            
            labelsToAdd.append((text, message.frequency))
            
            if let audioSamples = msgDict["audioSamples"] as? [Float] {
                waterfallSamples.append(contentsOf: audioSamples)
            }
            
            // Filtering / visibility is handled at RX list level (decodeSelfTXMessages).
            // Self TX messages are always decoded, but optionally hidden from RX display.
            if !decodeSelfTXMessages,
               isSelfTXMessage(text: text, txMessage: txMessage.text) {
                appLogger.log(.info,"Skipped self TX message: \(text)")
                
                // Add anyways country pair
                let pair = CountryPair(sender: message.senderCountry, receiver: message.dxCountry.country != nil ? message.dxCountry : nil)
                
                if !newCountryPairs.contains(pair) {
                    newCountryPairs.append(pair)
//                    appLogger.log(
//                        .debug,
//                        """
//                        New country pair detected in the batch:
//                        Sender: \(pair.sender.country ?? "N/A")
//                        Coordinates: (\(pair.sender.coordinates?.lat, default: "N/A"), \(pair.sender.coordinates?.lon, default: "N/A"))
//                        Receiver: \(pair.receiver?.country ?? "N/A")
//                        Coordinates: (\(pair.receiver?.coordinates?.lat, default: "N/A"), \(pair.receiver?.coordinates?.lon, default: "N/A"))
//                        """
//                    )
                }
                
                continue
            }
            
            messagesToAdd.append(message)
            appLogger.log(.debug,"Added message: \(text)")
            
            // Track new DX locators
            if let dx = message.locator, !dx.isEmpty, !existingLocators.contains(dx) {
                newLocators.append(dx)
            }
            
            // Track new DX country pairs
            let pair = CountryPair(sender: message.senderCountry, receiver: message.dxCountry.country != nil ? message.dxCountry : nil)
            if !newCountryPairs.contains(pair) {
                newCountryPairs.append(pair)
//                appLogger.log(
//                    .debug,
//                    """
//                    New country pair detected in the batch:
//                    Sender: \(pair.sender.country ?? "N/A")
//                      Coordinates: (\(pair.sender.coordinates?.lat, default: "N/A"), \(pair.sender.coordinates?.lon, default: "N/A"))
//                    Receiver: \(pair.receiver?.country ?? "N/A")
//                      Coordinates: (\(pair.receiver?.coordinates?.lat, default: "N/A"), \(pair.receiver?.coordinates?.lon, default: "N/A"))
//                    """
//                )
            }

        }
        
        return BatchProcessResult(
            messages: messagesToAdd,
            labels: labelsToAdd,
            waterfallSamples: waterfallSamples,
            newLocators: newLocators,
            workedCountries: newCountryPairs,
            shouldResetFirstLoop: shouldResetFirstLoop
        )
    }
    
    // MARK: - Self TX Detection
    private func isSelfTXMessage(message: FT8Message, txMessage: FT8Message) -> Bool {
        guard let messageCallsign = message.callsign,
              let txCallsign = txMessage.callsign else {
            return false
        }
        
        return messageCallsign == txCallsign
    }
    
    
    private func isSelfTXMessage(text: String, txMessage: String) -> Bool {
        text == txMessage
    }
    
    // MARK: - Message Creation
    private static func createMessage(from dict: [String: Any], isFT4: Bool, selectedBand: FT8Message.Band, isTX: Bool) -> FT8Message {
        let text = (dict["text"] as? String) ?? ""
        let timestampRaw = (dict["timestamp"] as? Double) ?? (dict["time"] as? Double) ?? Date().timeIntervalSince1970
        let slotLen = isFT4 ? 7.5 : 15.0
        let computedTimestamp = Date(timeIntervalSince1970: timestampRaw - slotLen)
        
        let snr = (dict["snr"] as? Double) ?? (dict["snr_db"] as? Double) ?? .nan
        let freq = (dict["frequency"] as? Double) ?? .nan
        let timeOffset = (dict["timeDelta"] as? Double) ?? (dict["time"] as? Double) ?? .nan
        let ldpc = (dict["ldpcErrors"] as? Int) ?? (dict["ldpc_errors"] as? Int) ?? 0
        
        return FT8Message(
            text: text,
            mode: isFT4 ? .ft4 : .ft8,
            isRealtime: true,
            timestamp: computedTimestamp,
            measuredSNR: snr,
            frequency: freq,
            timeOffset: timeOffset,
            ldpcErrors: ldpc,
            isTX: isTX,
            band: selectedBand,
            allowsReply: true
        )
    }
}
