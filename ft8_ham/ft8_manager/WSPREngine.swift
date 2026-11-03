//
//  WSPREngine.swift
//  ft_ham
//
//  Swift wrapper over the WSPR static library (rust/wspr_ffi, C ABI over RR73).
//  Compiled only when WsprFFI.xcframework is linked into the target, so the app still
//  builds without the Rust toolchain. Build the framework with rust/wspr_ffi/build-ios.sh.
//

import Foundation
#if canImport(WsprFFI)
import WsprFFI
#endif

/// One decoded WSPR spot.
struct WSPRSpot: Sendable, Equatable {
    /// Message text as WSJT-X shows it: "K1ABC FN42 37", "PJ4/K1ABC 33", "<K1ABC> FN42AB 37".
    let text: String
    /// WSPR message type (1, 2 or 3).
    let messageType: Int
    /// Reported transmitter power, in dBm.
    let powerDBm: Int
    /// Signal centre, in Hz of audio (add the dial frequency for RF).
    let audioFrequencyHz: Double
    /// Start offset from the nominal start (1 s into the slot), in seconds.
    let dtSeconds: Double
    /// Frequency drift, in Hz per second.
    let driftHzPerSecond: Double
    /// SNR in a 2500 Hz reference bandwidth, in dB.
    let snrDB: Double
    /// Sync score, in standard deviations above noise.
    let syncScore: Double

    /// Callsign as transmitted ("K1ABC", "PJ4/K1ABC"; type 3 hashed calls keep their "<>").
    var callsign: String { text.split(separator: " ").first.map(String.init) ?? "" }

    /// Locator, when the message carries one (types 1 and 3).
    var locator: String? {
        let parts = text.split(separator: " ")
        return parts.count == 3 ? String(parts[1]) : nil
    }
}

enum WSPREngineError: Error, Equatable, LocalizedError {
    case invalidMessage
    case invalidFrequency
    case invalidSampleRate
    case decoderUnavailable
    case internalError(code: Int32)

    init(code: Int32) {
        switch code {
        case -2: self = .invalidMessage
        case -3: self = .invalidFrequency
        case -4: self = .invalidSampleRate
        default: self = .internalError(code: code)
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidMessage: return "Text does not pack into a WSPR message"
        case .invalidFrequency: return "WSPR audio frequency must be between 1400 and 1600 Hz"
        case .invalidSampleRate: return "Sample rate must be between 8 and 192 kHz"
        case .decoderUnavailable: return "WSPR decoder could not be created"
        case .internalError(let code): return "WSPR library error \(code)"
        }
    }
}

// MARK: - App-facing facade

/// Entry point used by the rest of the app. Always compiled; when WsprFFI is not linked,
/// `isAvailable` is false and the operations are no-ops.
enum WSPRSupport {
    private static let logger = AppLogger(category: "WSPR")

    /// True when the WSPR library is linked into this build.
    static let isAvailable: Bool = {
        #if canImport(WsprFFI)
        return true
        #else
        return false
        #endif
    }()

    /// Power levels a WSPR message can carry, in dBm.
    static let validPowerLevels: [Int] = [0, 3, 7, 10, 13, 17, 20, 23, 27, 30, 33, 37, 40, 43, 47, 50, 53, 57, 60]

    /// Allowed signal centres for transmission (Hz of audio).
    static let txFrequencyRange: ClosedRange<Float> = 1400...1600

    /// Beacon text for our station: "CALL GRID4 DBM", or "PFX/CALL DBM" (type 2) for
    /// compound callsigns, which cannot carry a locator in a single transmission.
    static func beaconMessage(callsign: String, locator: String, powerDBm: Int) -> String {
        let call = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        let grid = String(locator.uppercased().prefix(4))
        let power = validPowerLevels.min(by: { abs($0 - powerDBm) < abs($1 - powerDBm) }) ?? 37
        if call.contains("/") || grid.count < 4 {
            return "\(call) \(power)"
        }
        return "\(call) \(grid) \(power)"
    }

    /// Keeps a requested TX audio frequency inside the 200 Hz WSPR window.
    static func clampTXFrequency(_ hz: Float) -> Float {
        min(max(hz, txFrequencyRange.lowerBound), txFrequencyRange.upperBound)
    }

    /// Whether `text` is a valid WSPR message (false when the library is not linked).
    static func isValidMessage(_ text: String) -> Bool {
        #if canImport(WsprFFI)
        return WSPREngine.messageType(of: text) != nil
        #else
        return false
        #endif
    }

    /// Decodes one slot of Float32 PCM and returns decoder dictionaries in the same shape
    /// as the FT engine ("text", "snr", "timeDelta", "frequency", "timestamp") plus the
    /// WSPR extras "powerDBm", "drift", "messageType".
    static func decode(_ audio: Data, sampleRate: Double) -> [[String: Any]] {
        #if canImport(WsprFFI)
        guard let engine = WSPREngine.shared else {
            logger.error("WSPR decoder unavailable")
            return []
        }
        let samples: [Float] = audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let started = Date()
        do {
            let spots = try engine.decodeSlot(samples, sampleRate: sampleRate)
            let now = Date()
            logger.info("Decoded \(spots.count) WSPR spots in \(String(format: "%.1f", now.timeIntervalSince(started)))s")
            return spots.map { spot in
                [
                    "text": spot.text,
                    "snr": spot.snrDB,
                    "timeDelta": spot.dtSeconds,
                    "frequency": spot.audioFrequencyHz,
                    "timestamp": now.timeIntervalSince1970,
                    "powerDBm": spot.powerDBm,
                    "drift": spot.driftHzPerSecond,
                    "messageType": spot.messageType,
                ]
            }
        } catch {
            logger.error("WSPR decode failed: \(error.localizedDescription)")
            return []
        }
        #else
        logger.warning("WSPR decode requested but WsprFFI is not linked")
        return []
        #endif
    }

    /// One transmission (110.6 s) at 12 kHz as Float32 PCM, or nil on error / no library.
    static func generateAudio(_ text: String, audioFrequencyHz: Float) -> Data? {
        #if canImport(WsprFFI)
        let freq = clampTXFrequency(audioFrequencyHz)
        if freq != audioFrequencyHz {
            logger.warning("WSPR TX frequency \(audioFrequencyHz) Hz clamped to \(freq) Hz")
        }
        do {
            return try WSPREngine.generateAudio(text, audioFrequencyHz: freq, sampleRate: 12_000)
        } catch {
            logger.error("WSPR synthesis failed for '\(text)': \(error.localizedDescription)")
            return nil
        }
        #else
        logger.warning("WSPR TX requested but WsprFFI is not linked")
        return nil
        #endif
    }
}

#if canImport(WsprFFI)

/// WSPR encoder/decoder. Decoding is CPU-heavy (seconds per slot): call it off the main
/// thread. Calls are serialised internally, so one instance can be shared.
final class WSPREngine: @unchecked Sendable {

    /// Slot length (s). Slots start on even UTC minutes.
    static let slotDuration: TimeInterval = 120
    /// Transmission starts this long after the slot start (s).
    static let transmissionStartOffset: TimeInterval = 1
    /// Maximum spots returned per slot.
    private static let maxSpots = 256

    /// Version of the linked library.
    static var libraryVersion: String { String(cString: wspr_ffi_version()) }

    /// Shared decoder (keeps the callsign hash table across slots).
    static let shared: WSPREngine? = try? WSPREngine()

    private let decoder: OpaquePointer
    private let lock = NSLock()

    init() throws {
        guard let decoder = wspr_decoder_new() else { throw WSPREngineError.decoderUnavailable }
        self.decoder = decoder
    }

    deinit {
        wspr_decoder_free(decoder)
    }

    /// Callsigns learned so far (used to resolve type 3 messages in later slots).
    var knownCallsigns: Int {
        lock.withLock { wspr_decoder_known_callsigns(decoder) }
    }

    /// Decodes one 2-minute slot: mono samples with sample 0 at the even UTC minute.
    /// - Parameters:
    ///   - samples: audio at `sampleRate` (resampled to 12 kHz internally).
    ///   - deep: slower, slightly more sensitive search.
    func decodeSlot(_ samples: [Float], sampleRate: Double, deep: Bool = false) throws -> [WSPRSpot] {
        guard let rate = UInt32(exactly: sampleRate.rounded()) else {
            throw WSPREngineError.invalidSampleRate
        }
        var spots = [WsprSpot](repeating: WsprSpot(), count: Self.maxSpots)
        var count = 0
        let rc: Int32 = lock.withLock {
            samples.withUnsafeBufferPointer { input in
                spots.withUnsafeMutableBufferPointer { out in
                    wspr_decode(decoder, input.baseAddress, input.count, rate, deep ? 1 : 0,
                                out.baseAddress, out.count, &count)
                }
            }
        }
        // BUFFER_TOO_SMALL still fills the buffer; keep the first maxSpots.
        guard rc == WSPR_OK || rc == WSPR_ERR_BUFFER_TOO_SMALL else {
            throw WSPREngineError(code: rc)
        }
        return spots.prefix(min(count, Self.maxSpots)).map(WSPRSpot.init(cSpot:))
    }

    /// Message type (1, 2 or 3) if `text` is a valid WSPR message, else nil.
    static func messageType(of text: String) -> Int? {
        let rc = wspr_message_type(text)
        return rc > 0 ? Int(rc) : nil
    }

    /// Generates one transmission (110.6 s, peak amplitude 1) as Float32 PCM `Data`,
    /// ready for `AudioManager.playAudio`. Start playback 1 s after an even UTC minute.
    static func generateAudio(
        _ text: String,
        audioFrequencyHz: Float = 1500,
        sampleRate: Int = 12_000
    ) throws -> Data {
        guard let rate = UInt32(exactly: sampleRate) else { throw WSPREngineError.invalidSampleRate }
        let n = wspr_transmission_samples(rate)
        guard n > 0 else { throw WSPREngineError.invalidSampleRate }
        var audio = [Float](repeating: 0, count: n)
        var written = 0
        let rc = audio.withUnsafeMutableBufferPointer { out in
            wspr_synthesize(text, audioFrequencyHz, rate, out.baseAddress, out.count, &written)
        }
        guard rc == WSPR_OK else { throw WSPREngineError(code: rc) }
        return audio.prefix(written).withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

private extension WSPRSpot {
    init(cSpot s: WsprSpot) {
        var raw = s.text
        let text = withUnsafeBytes(of: &raw) { buf in
            String(decoding: buf.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        self.init(
            text: text,
            messageType: Int(s.message_type),
            powerDBm: Int(s.power_dbm),
            audioFrequencyHz: Double(s.freq_hz),
            dtSeconds: Double(s.dt_s),
            driftHzPerSecond: Double(s.drift_hz_per_s),
            snrDB: Double(s.snr_db),
            syncScore: Double(s.score)
        )
    }
}
#endif
