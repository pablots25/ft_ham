//
//  Validators.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/11/25.
//

import Foundation

// MARK: Validators

// Compiled once. `String.range(of:options:.regularExpression)` re-parses the
// pattern on every call, and these validators run on every view body that
// reads `settingsLoaded`. The callsign pattern is compiled the same way inside
// `CompoundCallsign`, which owns callsign parsing.
private let locatorRegex = try! NSRegularExpression(pattern: #"^[A-R]{2}\d{2}$"#)

private func wholeMatch(_ regex: NSRegularExpression, _ text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

func isValidLocator(_ text: String) -> Bool {
    let upper = text.uppercased()

    if upper == "RR73" {
        return false
    }

    // Maidenhead 4-character locator
    return wholeMatch(locatorRegex, upper)
}

/// True when `text` is a callsign the app can work with.
///
/// Accepts plain calls ("VE6XAD"), calls carrying a foreign prefix
/// ("I/VE6XAD") and calls carrying a suffix ("VE6XAD/P", "W1AW/VE3").
/// See `CompoundCallsign` for the exact grammar.
func isValidCallsign(_ text: String) -> Bool {
    CompoundCallsign.parse(text) != nil
}


func isSignalReport(_ token: Substring) -> Bool {
    let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    // Single zero is a valid report
    if raw == "0" { return true }

    // "73" is a protocol farewell token, not a signal report
    if raw == "73" { return false }

    // Handle optional leading 'R' (ack) e.g. R+12, R-8
    var text = raw
    if text.hasPrefix("R") {
        text = String(text.dropFirst())
    }

    // Allow optional leading +/- sign
    var signRemoved = text
    if signRemoved.hasPrefix("+") || signRemoved.hasPrefix("-") {
        signRemoved = String(signRemoved.dropFirst())
    }

    // Now signRemoved must be 1-2 digits
    guard signRemoved.count >= 1 && signRemoved.count <= 2, Int(signRemoved) != nil else {
        return false
    }

    // If there was an R prefix it's valid (R+nn / R-nn), otherwise plain +nn / -nn / nn are valid
    return true
}

private func isValidFT8Message(_ message: String) -> Bool {
    let allowedChars = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ /+-")
    let filtered = message.uppercased().components(separatedBy: allowedChars.inverted).joined()
    
    return message.count <= 18 && message == filtered
}
