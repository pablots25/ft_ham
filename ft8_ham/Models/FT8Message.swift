//
//  FT8Message.swift
//  ft_ham
//
//  Created by Pablo Turrion on 15/11/25.
//

import Foundation

enum FT8MessageType: String, Codable, CaseIterable {
    case internalTimestamp
    case cq
    case gridExchange
    case standardSignalReport
    case rSignalReport
    case rr73
    case rrr
    case final73
    case unknown
}

enum FT8MessageCycle: String, Codable, CaseIterable {
    case odd
    case even
}

struct Coordinates: Codable, Hashable {
    let lat: Double
    let lon: Double
    
    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = -lon // normalization
    }
}

struct CountryInfo: Codable, Hashable {
    let country: String?
    let coordinates: Coordinates?
}

struct CountryPair: Hashable {
    let sender: CountryInfo
    let receiver: CountryInfo?

    func hash(into hasher: inout Hasher) {
        hasher.combine(sender)
        if let receiver = receiver {
            hasher.combine(receiver)
        } else {
            hasher.combine(0)
        }
    }

    static func ==(lhs: CountryPair, rhs: CountryPair) -> Bool {
        lhs.sender == rhs.sender && lhs.receiver == rhs.receiver
    }
}


// -----------------------------------------------------
struct FT8Message: Identifiable, Codable, CustomStringConvertible {
    static let appLogger = AppLogger(category: "MSG")
    
    let id: UUID
    let text: String
    let mode: FT8MessageMode
    let band: Band
    let isRealtime: Bool
    let timestamp: Date
    let cycle: FT8MessageCycle
    let measuredSNR: Double    // Measured by us        -> QSO - RST_SENT
    let messageTxtSNR: Double // Included in the text  ->  QSO - RST_RCVD
    let frequency: Double
    let timeOffset: Double
    let ldpcErrors: Int
    let msgType: FT8MessageType
    let forMe: Bool
    let isTX: Bool
    let allowsReply: Bool
    
    let callsign: String?      // Sender
    let locator: String?       // Sender
    let dxCallsign: String?    // Receiver
    let dxLocator: String?     // Receiver
    let cqModifier: String?
    
    let senderCountry: CountryInfo
    let dxCountry: CountryInfo
    
    init(
        text: String,
        mode: FT8MessageMode,
        isRealtime: Bool = false,
        timestamp: Date = .now,
        measuredSNR: Double = .nan,
        frequency: Double = .nan,
        timeOffset: Double = .nan,
        ldpcErrors: Int = .zero,
        isTX: Bool = false,
        band: Band = .unknown,
        allowsReply: Bool = true
    ) {
        id = UUID()
        self.text = text
        self.mode = mode
        self.isRealtime = isRealtime
        self.timestamp = timestamp
        self.measuredSNR = measuredSNR
        self.frequency = frequency
        self.timeOffset = timeOffset
        self.ldpcErrors = ldpcErrors
        self.isTX = isTX
        self.band = band
        
        // Assign TX cycle based on timestamp and mode (FT4 / FT8)
        self.cycle = FT8Message.calculateCycle(from: timestamp, mode: mode)
        
        // Parse message once for all operations
        let parts = FT8Message.splitParts(text)
        
        // Auto-detect FT8 message type
        msgType = FT8Message.detectMessageType(text: text, parts: parts)
        self.messageTxtSNR = FT8Message.extractSNR(parts: parts, type: msgType)
        
        self.allowsReply = (msgType != .unknown && !isTX) ? allowsReply : false
        
        // Extract sender / receiver information
        let participants = FT8Message.parseParticipants(parts: parts)
        
        // Assign sender info
        callsign = participants.senderCallsign
        locator = participants.senderLocator
        if let call = callsign {
            senderCountry = CountryResolver.countryAndCoordinates(for: call)
        } else {
            senderCountry = CountryInfo(country: nil, coordinates: nil)
        }
                
        // Assign receiver info
        dxCallsign = participants.receiverCallsign
        dxLocator = participants.receiverLocator
        if let dx = dxCallsign {
            dxCountry = CountryResolver.countryAndCoordinates(for: dx)
        } else {
            dxCountry = CountryInfo(country: nil, coordinates: nil)
        }

        cqModifier = FT8Message.parseCQStructure(parts)?.modifier
        
        let myCallsign = UserDefaults.standard.string(forKey: "callsign")

        if let my = myCallsign, !my.isEmpty {
            forMe = FT8Message.isForMe(
                participants: participants,
                myCallsign: my,
                isTX: isTX
            )
        } else {
            forMe = false
        }

        let snrDisplay = measuredSNR.isNaN ? "N/A" : String(format: "%.0f", measuredSNR)
        FT8Message.appLogger.debug("New message: \(self.text) (\(self.msgType), SNR: \(snrDisplay))")
    }
    
    // Convenience initializer for internal timestamp messages
    init(
        text: String,
        mode: FT8MessageMode,
        timestamp: Date,
        band: Band = .unknown,
        msgType: FT8MessageType = .internalTimestamp
    ) {
        id = UUID()
        self.text = text
        self.mode = mode
        self.band = band
        self.isRealtime = true
        self.timestamp = timestamp
        self.cycle = FT8Message.calculateCycle(from: timestamp, mode: mode)
        self.measuredSNR = .nan
        self.messageTxtSNR = .nan
        self.frequency = .nan
        self.timeOffset = .nan
        self.ldpcErrors = 0
        self.isTX = false
        self.allowsReply = false
        self.msgType = msgType
        self.forMe = false
        self.callsign = nil
        self.locator = nil
        self.dxCallsign = nil
        self.dxLocator = nil
        self.cqModifier = nil
        self.senderCountry = CountryInfo(country: nil, coordinates: nil)
        self.dxCountry = CountryInfo(country: nil, coordinates: nil)
    }
    
    // MARK: - TX Cycle Calculation
    static func calculateCycle(from date: Date, mode: FT8MessageMode) -> FT8MessageCycle {
        let calendar = Calendar(identifier: .gregorian)
        let seconds = calendar.component(.second, from: date)
        
        switch mode {
        case .ft8:
            // FT8 slots: 0–14, 15–29, 30–44, 45–59
            let slotIndex = seconds / 15
            return slotIndex.isMultiple(of: 2) ? .even : .odd
            
        case .ft4:
            // FT4 slots alternate every 7.5 s: even [0,15,30,45], odd [7.5,22.5,37.5,52.5]
            let slotIndex = Int(Double(seconds) / 7.5)
            return slotIndex.isMultiple(of: 2) ? .even : .odd
        }
    }
    
    // MARK: - Static Factory Methods
    static func timestamped(_ text: String, mode: FT8MessageMode, realtime: Bool = false, isTx: Bool) -> FT8Message {
        FT8Message(text: text, mode: mode, isRealtime: realtime, timestamp: .now, isTX: isTx)
    }
    
    static func decode(
        text: String,
        mode: FT8MessageMode,
        snr: Double,
        frequency: Double,
        timeOffset: Double,
        realtime: Bool = false
    ) -> FT8Message {
        FT8Message(
            text: text,
            mode: mode,
            isRealtime: realtime,
            timestamp: .now,
            measuredSNR: snr,
            frequency: frequency,
            timeOffset: timeOffset,
            isTX: false
        )
    }
    
    // MARK: - Message Mode
    enum FT8MessageMode: String, Codable {
        case ft4
        case ft8
    }
    
    // MARK: - Band
    enum Band: String, Codable, CaseIterable {
        case band160m = "160m"
        case band80m  = "80m"
        case band60m  = "60m"
        case band40m  = "40m"
        case band30m  = "30m"
        case band20m  = "20m"
        case band17m  = "17m"
        case band15m  = "15m"
        case band12m  = "12m"
        case band10m  = "10m"
        case band6m   = "6m"
        case unknown  = "Unknown"

        // Returns the standard dial frequency in Hz for the given mode.
        // Returns nil if the band/mode combination is not supported.
        func frequency(for mode: FT8MessageMode) -> Double? {
            switch mode {
            case .ft8:
                switch self {
                case .band160m: return 1_840_000
                case .band80m:  return 3_574_000
                case .band60m:  return 5_357_000
                case .band40m:  return 7_074_000
                case .band30m:  return 10_136_000
                case .band20m:  return 14_074_000
                case .band17m:  return 18_074_000
                case .band15m:  return 21_074_000
                case .band12m:  return 24_915_000
                case .band10m:  return 28_074_000
                case .band6m:   return 50_313_000
                case .unknown:  return nil
                }

            case .ft4:
                switch self {
                case .band160m: return 1_840_000
                case .band80m:  return 3_575_000
                case .band60m:  return 5_357_000
                case .band40m:  return 7_047_500
                case .band30m:  return 10_140_000
                case .band20m:  return 14_080_000
                case .band17m:  return 18_104_000
                case .band15m:  return 21_140_000
                case .band12m:  return 24_919_000
                case .band10m:  return 28_080_000
                case .band6m:   return 50_318_000
                case .unknown:  return nil
                }
            }
        }

        static var validBands: [Band] {
            allCases.filter { $0 != .unknown }
        }
    }

    
    // MARK: - FT8 CQ Token Whitelist (from WSJT-X grammar)
    static let validCQTokens: Set<String> = [
        "DX","EU","NA","SA","AF","AS","OC","ANT",
        "POTA","SOTA","WWFF","IOTA"
    ]

    // MARK: - Parsing helpers
    private static func splitParts(_ text: String) -> [Substring] {
        text.uppercased().split(separator: " ")
    }

    // MARK: - Internal CQ grammar parser
    private static func parseCQStructure(_ parts: [Substring]) -> (
        modifier: String?,
        callsign: String?,
        locator: String?
    )? {
        guard parts.count >= 2, parts[0] == "CQ" else {
            return nil
        }

        // CQ CALL [GRID]
        if isValidCallsign(String(parts[1])) {
            let locator = (parts.count >= 3 && isValidLocator(String(parts[2])))
                ? String(parts[2])
                : nil

            return (nil, String(parts[1]), locator)
        }

        // CQ TOKEN CALL [GRID]
        if parts.count >= 3,
           validCQTokens.contains(String(parts[1])),
           isValidCallsign(String(parts[2])) {

            let locator = (parts.count >= 4 && isValidLocator(String(parts[3])))
                ? String(parts[3])
                : nil

            return (String(parts[1]), String(parts[2]), locator)
        }

        return nil
    }

    static func extractCQModifier(from text: String) -> String? {
        let parts = text.uppercased().split(separator: " ")
        return parseCQStructure(parts)?.modifier
    }

    // MARK: - Participant Parsing
    static func parseParticipants(
        parts: [Substring]
    ) -> (
        senderCallsign: String?,
        senderLocator: String?,
        receiverCallsign: String?,
        receiverLocator: String?
    ) {
        guard parts.count >= 2 else {
            return (nil, nil, nil, nil)
        }

        if let cq = parseCQStructure(parts) {
            return (cq.callsign, cq.locator, nil, nil)
        }

        // <receiver> <sender> <xxx>
        guard isValidCallsign(String(parts[0])),
              isValidCallsign(String(parts[1])) else {
            return (nil, nil, nil, nil)
        }

        let receiverCall = String(parts[0])
        let senderCall = String(parts[1])

        var senderLocator: String? = nil
        if parts.count >= 3, isValidLocator(String(parts[2])) {
            senderLocator = String(parts[2])
        }

        return (
            senderCallsign: senderCall,
            senderLocator: senderLocator,
            receiverCallsign: receiverCall,
            receiverLocator: nil
        )
    }

    
    
    // MARK: - Message Type Detection
    static func detectMessageType(text: String, parts: [Substring]) -> FT8MessageType {
        guard !parts.isEmpty else { return .unknown }
        
        if isInternalTimestamp(text) {
            return .internalTimestamp
        }
        
        if parseCQStructure(parts) != nil {
            return .cq
        }
        
        let p = parseParticipants(parts: parts)
        
        if let s = p.senderCallsign,
           let r = p.receiverCallsign {
            
            if parts.contains("RR73") { return .rr73 }
            if parts.contains("RRR") { return .rrr }
            if parts.contains("73") { return .final73 }
            
            if parts.count == 3,
            let locator = p.senderLocator,
            isValidLocator(locator) {
                return .gridExchange
            }
            
            if parts.count == 3,
            isSignalReport(parts[2]) {
                return parts[2].contains("R")
                    ? .rSignalReport
                    : .standardSignalReport
            }
        }
        
        return .unknown
    }
    
    
    // MARK: - Internal Timestamp Helper
    private static func isInternalTimestamp(_ text: String) -> Bool {
        // Expected format: "yyyy-MM-dd HH:mm:ss - BAND"
        // Since yyyy-MM-dd contains dashes, we should split on " - " specifically
        let components = text.components(separatedBy: " - ")
        guard components.count == 2 else { return false }
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return formatter.date(from: components[0]) != nil
    }
    
    // MARK: - Is for me?
    static func isForMe(
        participants: (
            senderCallsign: String?,
            senderLocator: String?,
            receiverCallsign: String?,
            receiverLocator: String?
        ),
        myCallsign: String,
        isTX: Bool
    ) -> Bool {
        let my = myCallsign.uppercased()

        if let sender = participants.senderCallsign?.uppercased(),
        sender == my {
            return true
        }

        if let receiver = participants.receiverCallsign?.uppercased(),
        receiver == my {
            return true
        }

        return false
    }    
    
    // MARK: - Extract SNR from text
    static func extractSNR(parts: [Substring], type: FT8MessageType) -> Double {
        guard !parts.isEmpty else { return .nan }
        
        func parseNumber(_ str: String) -> Double? {
            var s = str
            if s.hasPrefix("R") {
                s.removeFirst()
            }
            if let v = Int(s), v >= -30, v <= 30 {
                return Double(v)
            }
            return nil
        }
        
        switch type {
        case .cq, .internalTimestamp:
            return .nan   // no SNR in CQ or timestamp messages
            
        default:
            for part in parts {
                if let snr = parseNumber(String(part)) {
                    return snr
                }
            }
            return .nan
        }
    }
    
    // MARK: - Utilities
    static func empty() -> FT8Message {
        FT8Message(
            text: "",
            mode: .ft8,
            isRealtime: false,
            timestamp: .now,
            isTX: false
        )
    }
    
    // MARK: - Pretty Printing
    var description: String {
        """
        FT8Message:
          text: "\(text)"
          mode: \(mode.rawValue)
          band: \(band.rawValue) (\(band.frequency(for: mode)) Hz)
          timestamp: \(timestamp)
          cycle: \(cycle.rawValue)
          isRealtime: \(isRealtime)
          measuredSNR: \(measuredSNR)
          frequency: \(frequency)
          timeOffset: \(timeOffset)
          ldpcErrors: \(ldpcErrors)
          msgType: \(msgType.rawValue)
          isTX: \(isTX)
          allowsReply: \(allowsReply)
          forMe: \(forMe)
          callsign: \(callsign ?? "-")
          locator: \(locator ?? "-")
          dxCallsign: \(dxCallsign ?? "-")
          dxLocator: \(dxLocator ?? "-")
          senderCountry: \(senderCountry.country ?? "-") (\(senderCountry.coordinates?.lat ?? 0), \(senderCountry.coordinates?.lon ?? 0))
          dxCountry: \(dxCountry.country ?? "-") (\(dxCountry.coordinates?.lat ?? 0), \(dxCountry.coordinates?.lon ?? 0))
        """
    }
}

