//
//  AudioErrorToastText.swift
//  ft_ham
//

import Foundation

/// Short, translated wording for an audio error shown as a toast. Audio errors
/// arrive as technical English text (often with an OSStatus), which is too
/// long for a toast and means little to the operator. The full text still
/// goes to the log.
enum AudioErrorToastText {

    /// The toast text for a raw audio error message.
    static func message(for raw: String) -> String {
        switch kind(of: raw) {
        case .setup:
            return String(localized: "Couldn't set up audio. Check your audio device.")
        case .engineStart:
            return String(localized: "Audio couldn't start. Check your audio device.")
        case .microphone:
            return String(localized: "Can't read the audio input. Check your audio device.")
        case .noOutput:
            return String(localized: "No audio output. Check your audio device.")
        case .txAudio:
            return String(localized: "Couldn't create the TX audio.")
        case .station:
            return String(localized: "Check your callsign and locator in Configuration.")
        case .unknown:
            return String(localized: "Audio problem. Check your audio device.")
        }
    }

    enum Kind: Equatable {
        case setup, engineStart, microphone, noOutput, txAudio, station, unknown
    }

    /// Groups raw messages by the prefixes `AudioManager` and the sequencer use.
    static func kind(of raw: String) -> Kind {
        let prefixes: [(String, Kind)] = [
            ("Failed to configure audio session", .setup),
            ("Failed to set preferred sample rate", .setup),
            ("Failed to activate audio session", .setup),
            ("Invalid input format", .setup),
            ("Failed to start audio engine", .engineStart),
            ("Audio engine not running", .engineStart),
            ("Failed to install microphone tap", .microphone),
            ("No audio output available", .noOutput),
            ("Failed to generate audio", .txAudio),
            ("Invalid audio data", .txAudio),
            ("Invalid callsign/locator", .station),
        ]
        return prefixes.first { raw.hasPrefix($0.0) }?.1 ?? .unknown
    }
}
