//
//  Validators.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/11/25.
//

// MARK: Validators

func isValidLocator(_ text: String) -> Bool {
    let upper = text.uppercased()

    if upper == "RR73" {
        return false
    }

    // Maidenhead 4-character locator
    let pattern = #"^[A-R]{2}\d{2}$"#
    return upper.range(of: pattern, options: .regularExpression) != nil
}

func isValidCallsign(_ text: String) -> Bool {
    let upper = text.uppercased()

    // protocol tokens that are NOT callsigns
    let forbiddenTokens: Set<String> = [
        "CQ",
        "QRZ",
        "DE",
        "RR73",
        "73"
    ]

    if forbiddenTokens.contains(upper) {
        return false
    }

    // Excludes anything that looks like a locator or a signal report
    if isValidLocator(upper) {
        return false
    }

    if isSignalReport(Substring(upper)) {
        return false
    }

    // FT8/FT4 callsign validation: 
    // In FT8, any callsign with "/" is valid - there's no closed list of modifiers
    // 1–3 alphanumeric prefix characters
    // Exactly one digit  
    // 1–3 trailing letters
    // Optional: slash followed by any alphanumeric suffix (P, MM, QRP, 1, /ABC, etc.)
    // Multiple suffixes are NOT allowed
    let pattern = #"^[A-Z0-9]{1,3}\d[A-Z]{1,3}(/[A-Z0-9]+)?$"#

    return upper.range(of: pattern, options: .regularExpression) != nil
}


func isSignalReport(_ token: Substring) -> Bool {
    let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    // Single zero is a valid report
    if raw == "0" { return true }

    // Handle optional leading 'R' (ack) e.g. R+12, R-8
    var text = raw
    var hasRPrefix = false
    if text.hasPrefix("R") {
        hasRPrefix = true
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
