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
        hasher.combine(receiver)
    }

    static func ==(lhs: CountryPair, rhs: CountryPair) -> Bool {
        lhs.sender == rhs.sender && lhs.receiver == rhs.receiver
    }
}


// -----------------------------------------------------
struct FT8Message: Identifiable, Codable, Equatable, CustomStringConvertible {
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
        timestamp: Date = AppClock.now(),
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
        
        FT8Message.ensureCallsignCacheInitialized()

        if let my = FT8Message.cachedCallsign, !my.isEmpty {
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
        // FT8 slots: 0–14, 15–29, 30–44, 45–59
        // FT4 slots alternate every 7.5 s: even [0,15,30,45], odd [7.5,22.5,37.5,52.5]
        // Uses the fractional epoch time (not whole seconds) so fractional slot boundaries are exact.
        // Every slot length divides 60 s an even number of times, so parity matches the
        // per-minute convention.
        let slotIndex = Int(floor(date.timeIntervalSince1970 / mode.slotDuration))
        return slotIndex.isMultiple(of: 2) ? .even : .odd
    }
    
    // MARK: - Static Factory Methods
    static func timestamped(_ text: String, mode: FT8MessageMode, realtime: Bool = false, isTx: Bool) -> FT8Message {
        FT8Message(text: text, mode: mode, isRealtime: realtime, timestamp: AppClock.now(), isTX: isTx)
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
            timestamp: AppClock.now(),
            measuredSNR: snr,
            frequency: frequency,
            timeOffset: timeOffset,
            isTX: false
        )
    }
    
    // MARK: - Message Mode
    /// Kept as an alias so existing code and persisted data ("ft4"/"ft8") keep working.
    typealias FT8MessageMode = DigitalMode
    
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
        case band11m  = "CB/11m"
        case band10m  = "10m"
        case band6m   = "6m"
        case band2m   = "2m"
        case band125m = "1.25m"
        case band70cm = "70cm"
        case band33cm = "33cm"
        case band23cm = "23cm"
        case custom   = "Custom"
        case unknown  = "Unknown"

        // Returns the standard dial frequency in Hz for the given mode.
        // Returns nil if the band/mode combination is not supported.
        func frequency(for mode: FT8MessageMode) -> Double? {
            switch mode {
            case .ft8:
                switch self {
                case .band160m: return 1_840_000
                case .band80m:  return 3_573_000
                case .band60m:  return 5_357_000
                case .band40m:  return 7_074_000
                case .band30m:  return 10_136_000
                case .band20m:  return 14_074_000
                case .band17m:  return 18_100_000
                case .band15m:  return 21_074_000
                case .band12m:  return 24_915_000
                case .band11m:  return 27_245_000
                case .band10m:  return 28_074_000
                case .band6m:   return 50_313_000
                case .band2m:   return 144_174_000
                case .band125m: return 222_174_000
                case .band70cm: return 432_174_000
                case .band33cm: return 902_174_000
                case .band23cm: return 1_296_174_000
                case .custom:   return nil
                case .unknown:  return nil
                }

            case .ft4:
                switch self {
                case .band160m: return 1_840_000         // No standard FT4 frequency
                case .band80m:  return 3_575_000
                case .band60m:  return 5_357_000         // No standard FT4 frequency
                case .band40m:  return 7_047_500
                case .band30m:  return 10_140_000
                case .band20m:  return 14_080_000
                case .band17m:  return 18_104_000
                case .band15m:  return 21_140_000
                case .band12m:  return 24_919_000
                case .band11m:  return 27_245_000         // No standard FT4 frequency
                case .band10m:  return 28_180_000
                case .band6m:   return 50_318_000
                case .band2m:   return 144_170_000
                case .band125m: return 222_170_000
                case .band70cm: return 432_170_000
                case .band33cm: return 902_170_000
                case .band23cm: return 1_296_170_000
                case .custom:   return nil
                case .unknown:  return nil
                }
            }
        }

        static var validBands: [Band] {
            allCases.filter { $0 != .unknown }
        }

        // MARK: - Detect band from a dial frequency in Hz
        // Uses standard ITU amateur radio band allocations.
        // Returns .unknown if the frequency does not fall within a known ham band.
        static func fromFrequency(_ hz: Double) -> Band {
            let mhz = hz / 1_000_000
            switch mhz {
            case 1.8..<2.0:        return .band160m
            case 3.5..<4.0:        return .band80m
            case 5.3505..<5.3665:  return .band60m
            case 7.0..<7.3:        return .band40m
            case 10.1..<10.15:     return .band30m
            case 14.0..<14.35:     return .band20m
            case 18.068..<18.168:  return .band17m
            case 21.0..<21.45:     return .band15m
            case 24.89..<24.99:    return .band12m
            case 26.96..<27.41:    return .band11m
            case 28.0..<29.7:      return .band10m
            case 50.0..<54.0:      return .band6m
            case 144.0..<148.0:    return .band2m
            case 222.0..<225.0:    return .band125m
            case 420.0..<450.0:    return .band70cm
            case 902.0..<928.0:    return .band33cm
            case 1240.0..<1300.0:  return .band23cm
            default:               return .unknown
            }
        }

        // MARK: - ADIF band name
        // The name ADIF expects for this band, which is not always the label we
        // show in the picker: "CB/11m" reads better in the UI but ADIF only
        // knows "11m". Returns nil for bands that have no ADIF name at all
        // (.custom carries no band of its own, .unknown is not a band).
        var adifName: String? {
            switch self {
            case .band11m:            return "11m"
            case .custom, .unknown:   return nil
            default:                  return rawValue
            }
        }

        // MARK: - ADIF BAND for a logged QSO
        // Resolves the BAND to export for a QSO. The dial frequency wins when we
        // have one and it lands in a known band: the stored band is whatever the
        // operator picked by hand and can disagree with where the radio actually
        // was. Falls back to the stored band, and passes an unrecognised stored
        // value through untouched so imported logs keep their original BAND.
        // Returns nil when no band can be established, so the caller omits the field.
        static func adifBand(frequencyHz: Double?, storedBand: String) -> String? {
            if let hz = frequencyHz {
                let detected = fromFrequency(hz)
                if detected != .unknown { return detected.adifName }
            }

            let trimmed = storedBand.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let known = Band(rawValue: trimmed) { return known.adifName }
            return trimmed
        }
    }

    
    // MARK: - FT8 CQ Token Whitelist (TX presets)
    static let validCQTokens: Set<String> = [
        "DX","EU","NA","SA","AF","AS","OC","ANT",
        "POTA","SOTA","WWFF","IOTA"
    ]

    private(set) static var cachedCallsign: String?
    private static var callsignObserver: NSObjectProtocol?
    private static var isCallsignCacheInitialized = false

    private static func ensureCallsignCacheInitialized() {
        guard !isCallsignCacheInitialized else { return }

        isCallsignCacheInitialized = true
        cachedCallsign = UserDefaults.standard.string(forKey: "callsign")?.uppercased()

        callsignObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            cachedCallsign = UserDefaults.standard.string(forKey: "callsign")?.uppercased()
        }
    }

    // MARK: - RX CQ modifier validation (permissive)
    // For receive-side parsing we accept any plausible CQ modifier token,
    // keeping it raw without canonical interpretation.
    private static func isPlausibleCQModifier(_ token: Substring) -> Bool {
        let upper = String(token).uppercased()

        guard !upper.isEmpty else { return false }

        // Protocol words and values that are not modifiers
        let protocolTokens: Set<String> = ["CQ", "QRZ", "DE", "RR73", "73"]
        if protocolTokens.contains(upper) {
            return false
        }

        if isValidCallsign(upper) || isValidLocator(upper) || isSignalReport(Substring(upper)) {
            return false
        }

        let pattern = #"^[A-Z0-9/]{1,4}$"#
        return upper.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Parsing helpers
    private static func splitParts(_ text: String) -> [Substring] {
        text.uppercased().split(separator: " ")
    }

    /// Reads one decoded token as a callsign, or returns `nil` when it is not one.
    ///
    /// A station using a compound callsign is referred to by a hash once its
    /// call has been sent in plain text, and the decoder prints that hash in
    /// angle brackets: `<VE6XAD>` when it knows the call, `<...>` when it does
    /// not. The brackets are stripped so the rest of the app sees a plain
    /// callsign, and an unresolved hash reads as no callsign at all.
    static func callsign(from token: Substring) -> String? {
        CompoundCallsign.fromDecodedToken(token)?.text
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
        if let call = callsign(from: parts[1]) {
            let locator = (parts.count >= 3 && isValidLocator(String(parts[2])))
                ? String(parts[2])
                : nil

            return (nil, call, locator)
        }

          // CQ TOKEN CALL [GRID]
        if parts.count >= 3,
              isPlausibleCQModifier(parts[1]),
           let call = callsign(from: parts[2]) {

            let locator = (parts.count >= 4 && isValidLocator(String(parts[3])))
                ? String(parts[3])
                : nil

            return (String(parts[1]), call, locator)
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
        guard let receiverCall = callsign(from: parts[0]),
              let senderCall = callsign(from: parts[1]) else {
            // Partial decode: the called-callsign field was not decoded, but the
            // calling callsign is valid. Extract sender info so that the message
            // type can still be inferred from the remaining fields (grid, signal
            // report, RR73, etc.) using the standard detection logic.
            //
            // This also covers a station calling someone whose compound call the
            // decoder has not yet heard spelled out, which arrives as "<...>".
            guard let senderCall = callsign(from: parts[1]) else {
                return (nil, nil, nil, nil)
            }
            var senderLocator: String? = nil
            if parts.count >= 3, isValidLocator(String(parts[2])) {
                senderLocator = String(parts[2])
            }
            return (
                senderCallsign: senderCall,
                senderLocator: senderLocator,
                receiverCallsign: nil,
                receiverLocator: nil
            )
        }

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
        
        // Apply type inference whenever the sender callsign is decoded.
        // This covers both fully-decoded messages (receiverCallsign != nil) and
        // partially-decoded ones where the called-callsign field was unreadable —
        // the message type is inferred from the content (grid, signal report, etc.)
        if p.senderCallsign != nil {
            
            if parts.contains("RR73") { return .rr73 }
            if parts.contains("RRR") { return .rrr }
            if parts.contains("73") { return .final73 }
            
            if parts.count == 3,
               let locator = p.senderLocator,
               isValidLocator(locator) {
                return .gridExchange
            }

            // "K1ABC I/VE6XAD" — one station calling another with no exchange
            // field. This is how a compound callsign answers a CQ, because the
            // message type that spells the call out has no room for a grid. It
            // opens a QSO exactly like a grid exchange does, only without the
            // grid, which the QSO flow already treats as optional.
            if parts.count == 2, p.receiverCallsign != nil {
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
        
        // Shared formatter (same "yyyy-MM-dd HH:mm:ss" UTC format); creating a
        // DateFormatter per decoded message is expensive.
        return DateFormatter.utcFormatterMessage.date(from: components[0]) != nil
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
            timestamp: AppClock.now(),
            isTX: false
        )
    }
    
    // MARK: - Pretty Printing
    var description: String {
        """
        FT8Message:
          text: "\(text)"
          mode: \(mode.rawValue)
          band: \(band.rawValue) (\(band.frequency(for: mode) ?? 0) Hz)
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

