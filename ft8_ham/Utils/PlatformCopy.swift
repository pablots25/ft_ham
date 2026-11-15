//
//  PlatformCopy.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/11/26.
//

import Foundation

/// How to reply to a decoded message, worded for the device in hand. On a
/// Mac there is no swipe and no vibration: a click (or double-click, with the
/// Reply gesture setting) replies, and a drag still works as a swipe.
enum ReplyGuidance {
    /// Text of the one-time tutorial over the received list.
    static func tutorialText(isMac: Bool, gesture: ReplyTapGesture) -> LocalizedStringResource {
        guard isMac else { return "tutorial_swipe_reply" }
        switch gesture {
        case .single: return "Click any received message to reply on the frequency it used."
        case .double: return "Double-click any received message to reply on the frequency it used."
        }
    }

    /// Title of the reply row in the Messages Guide.
    static func legendTitle(isMac: Bool, gesture: ReplyTapGesture) -> LocalizedStringResource {
        guard isMac else { return "Swipe right to reply" }
        switch gesture {
        case .single: return "Click to reply"
        case .double: return "Double-click to reply"
        }
    }

    /// Detail of the reply row in the Messages Guide.
    static func legendDetail(isMac: Bool, gesture: ReplyTapGesture) -> LocalizedStringResource {
        guard isMac else {
            return "On any received message, swipe right to pre-fill it as your current QSO target. A short vibration confirms the selection."
        }
        switch gesture {
        case .single:
            return "On any received message, click to pre-fill it as your current QSO target."
        case .double:
            return "On any received message, double-click to pre-fill it as your current QSO target."
        }
    }

    /// SF Symbol for the reply row in the Messages Guide.
    static func legendSymbol(isMac: Bool, gesture: ReplyTapGesture) -> String {
        guard isMac else { return "chevron.right.2" }
        return gesture == .double ? "cursorarrow.click.2" : "cursorarrow.click"
    }

    /// The Reply gesture setting as stored by `@AppStorage("replyTapGesture")`.
    static func storedGesture(_ defaults: UserDefaults = .standard) -> ReplyTapGesture {
        defaults.string(forKey: "replyTapGesture").flatMap(ReplyTapGesture.init(rawValue:)) ?? .single
    }
}

/// Audio settings copy that differs between a phone or tablet and a Mac.
enum AudioGuidance {
    /// Footnote under the audio level sliders. A Mac has no volume buttons,
    /// and its output level is set per device in System Settings.
    static func levelsFootnote(isMac: Bool) -> LocalizedStringResource {
        isMac
            ? "RX Gain: adjust input sensitivity for decoding. TX Output: raise if your radio's VOX won't activate."
            : "RX Gain: adjust microphone sensitivity for decoding. TX Output: raise if your radio's VOX won't activate (also ensure phone volume is at maximum)."
    }

    /// The "turn the volume up" hint reads the device volume, which a Mac
    /// sets per output device, so the hint only shows on iPhone and iPad.
    static func showsLowVolumeHint(isMac: Bool, volume: Float) -> Bool {
        !isMac && TXVolumeHint.shouldShow(forVolume: volume)
    }
}
