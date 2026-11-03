//
//  DigitalMode.swift
//  ft_ham
//
//  Single source of truth for every per-mode parameter (slot timing, signal
//  length, TX start tolerance, ADIF mode/submode, display name...).
//
//  New modes are added here as new cases; the rest of the app reads these
//  properties instead of branching on a `Bool`.
//

import Foundation

enum DigitalMode: String, Codable, CaseIterable, Sendable {
    case ft8
    case ft4

    // MARK: - Persistence

    /// UserDefaults key holding the selected mode (raw value).
    static let storageKey = "digitalMode"

    /// Legacy UserDefaults key (Bool) used before `DigitalMode` existed.
    static let legacyStorageKey = "isFT4"

    /// Reads the stored mode, migrating the legacy `isFT4` Bool if needed.
    static func loadStored(from defaults: UserDefaults = .standard) -> DigitalMode {
        if let raw = defaults.string(forKey: storageKey),
           let mode = DigitalMode(rawValue: raw) {
            return mode
        }
        let migrated: DigitalMode = defaults.bool(forKey: legacyStorageKey) ? .ft4 : .ft8
        defaults.set(migrated.rawValue, forKey: storageKey)
        return migrated
    }

    // MARK: - Display

    /// Human readable name ("FT8", "FT4").
    var displayName: String { rawValue.uppercased() }

    /// Whether the mode can be used in this build.
    var isAvailable: Bool { true }

    /// Modes offered in the UI.
    static var selectableCases: [DigitalMode] { allCases.filter(\.isAvailable) }

    // MARK: - Timing

    /// T/R slot length in seconds.
    var slotDuration: Double {
        switch self {
        case .ft8: return 15.0
        case .ft4: return 7.5
        }
    }

    /// Minimum audio (seconds) that must be captured to attempt a decode of a slot.
    /// Kept identical to the previous constants to preserve behaviour.
    var signalDuration: Double {
        switch self {
        case .ft8: return 12.6
        case .ft4: return 4.5
        }
    }

    /// Extra safety margin (seconds) added to `signalDuration` before decoding.
    var decodeMargin: Double {
        switch self {
        case .ft8: return 0.2
        case .ft4: return 0.1
        }
    }

    /// `signalDuration + decodeMargin`.
    var minimumDecodeDuration: Double { signalDuration + decodeMargin }

    /// Longest capture (s) handed to the decoder; longer RX buffers are trimmed.
    var maxCaptureDuration: Double { minimumDecodeDuration + 1.0 }

    /// Whether the decoder needs sample 0 at the slot start.
    /// When true, the sequencer pads the capture with the time lost before the buffer
    /// was reset at the slot boundary.
    var requiresSlotAlignedCapture: Bool { false }

    /// Delay (s) after the slot start before audio may start playing.
    var transmissionStartDelay: Double { 0 }

    /// Maximum allowed TX start offset (seconds) from slot start.
    /// Values chosen to preserve effective SNR.
    var maxStartOffset: Double {
        switch self {
        case .ft8: return 2.4
        case .ft4: return 0.8
        }
    }

    // MARK: - Signal

    /// Approximate occupied bandwidth (Hz) of a single signal, used for UI markers.
    var signalBandwidthHz: Double {
        switch self {
        case .ft8: return 50.0
        case .ft4: return 90.0
        }
    }

    /// Whether the mode supports two-way QSOs (false for beacon modes).
    var supportsQSO: Bool { true }

    // MARK: - Engine

    /// Protocol identifier passed to `ft8_Engine`; nil for modes handled elsewhere.
    var engineProtocol: FTXEngineProtocol? {
        switch self {
        case .ft8: return .ft8
        case .ft4: return .ft4
        }
    }

    // MARK: - Logging / Reporting

    /// Mode sent to PSK Reporter; nil for modes that are not reported there.
    var pskReporterMode: PSKReporterMode? {
        switch self {
        case .ft8: return .ft8
        case .ft4: return .ft4
        }
    }

    /// Mode string stored in the logbook and sent to external services ("FT8", "FT4").
    var logMode: String { displayName }

    /// ADIF MODE / SUBMODE pair as defined by the ADIF specification.
    /// FT4 is officially `MODE=MFSK SUBMODE=FT4`; FT8 is a top-level mode.
    var adif: (mode: String, submode: String?) {
        switch self {
        case .ft8: return ("FT8", nil)
        case .ft4: return ("MFSK", "FT4")
        }
    }
}
