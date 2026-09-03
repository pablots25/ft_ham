//
//  CompoundCallsign.swift
//  ft_ham
//
//  Parsing of compound (portable / travelling) callsigns.
//
//  A compound callsign carries a modifier separated by a slash:
//
//    * prefix form — "I/VE6XAD": a Canadian station operating from Italy.
//      The modifier comes first and it names the DXCC entity being operated from.
//    * suffix form — "VE6XAD/P", "VE6XAD/MM", "VE6XAD/1", "W1AW/VE3": the
//      modifier comes last. It either describes *how* the station is operating
//      (portable, mobile, maritime mobile, QRP...) or, when the suffix is itself
//      a DXCC prefix, *where* it is operating from.
//
//  Only one modifier is supported, which matches both the IARU convention and
//  what the FT8 protocol can carry: a non-standard callsign is transmitted as
//  11 characters of plain text in a type-4 message.
//

import Foundation

struct CompoundCallsign: Equatable {

    /// The modifier attached to a base callsign, and on which side it sits.
    enum Modifier: Equatable {
        case prefix(String)
        case suffix(String)

        var text: String {
            switch self {
            case .prefix(let value), .suffix(let value): return value
            }
        }
    }

    /// The plain callsign without its modifier, e.g. "VE6XAD" in "I/VE6XAD".
    let baseCall: String

    /// The modifier, or `nil` for a plain callsign such as "VE6XAD".
    let modifier: Modifier?

    /// The full normalised callsign, e.g. "I/VE6XAD".
    let text: String

    var isCompound: Bool { modifier != nil }

    // MARK: - Protocol limits

    /// A non-standard callsign travels as 11 characters of plain text in a
    /// type-4 FT8/FT4 message. Anything longer cannot be transmitted at all.
    static let maxLength = 11

    /// The longest modifier accepted on either side of the slash.
    static let maxModifierLength = 4

    // MARK: - Character tables

    /// Suffixes that describe the operation rather than the DXCC entity, so the
    /// country stays that of the base callsign. "/1"-style digit suffixes are
    /// handled separately because they are open-ended.
    static let operationalSuffixes: Set<String> = [
        "P",    // portable
        "M",    // mobile
        "MM",   // maritime mobile
        "AM",   // aeronautical mobile
        "A",    // secondary/alternate location (several administrations)
        "R",    // repeater / rover
        "B",    // beacon
        "QRP",  // low power
        "LH",   // lighthouse
        "J",    // jamboree
        "T",    // temporary
        "LGT"   // lightweight / light station
    ]

    /// Tokens that are part of the FT8 protocol grammar and can never be a call.
    static let protocolTokens: Set<String> = ["CQ", "QRZ", "DE", "RR73", "73"]

    // MARK: - Parsing

    /// Parses `text` into a callsign, or returns `nil` when it is not one.
    ///
    /// Accepts plain calls ("VE6XAD"), prefixed calls ("I/VE6XAD") and suffixed
    /// calls ("VE6XAD/P", "W1AW/VE3"). Rejects protocol tokens, grid locators,
    /// signal reports, multiple modifiers and anything too long to transmit.
    static func parse(_ text: String) -> CompoundCallsign? {
        var upper = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        upper.removeAll(where: { $0.isWhitespace })

        guard !upper.isEmpty, upper.count <= maxLength else { return nil }
        guard !protocolTokens.contains(upper) else { return nil }

        // Only A–Z, 0–9 and the modifier separator are legal in a callsign.
        guard upper.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "/") }) else {
            return nil
        }

        let parts = upper.split(separator: "/", omittingEmptySubsequences: false)

        switch parts.count {
        case 1:
            guard isStandardBaseCall(upper) else { return nil }
            return CompoundCallsign(baseCall: upper, modifier: nil, text: upper)

        case 2:
            let first = String(parts[0])
            let second = String(parts[1])
            guard !first.isEmpty, !second.isEmpty else { return nil }

            let firstIsBase = isStandardBaseCall(first)
            let secondIsBase = isStandardBaseCall(second)

            // "VE6XAD/P", "W1AW/VE3" — base call first, modifier last. Also the
            // tie-breaker when both halves look like a base call, matching the
            // usual "my call, then where I am" reading.
            if firstIsBase, isValidSuffix(second) {
                return CompoundCallsign(baseCall: first, modifier: .suffix(second), text: upper)
            }

            // "I/VE6XAD" — DXCC prefix first, base call last.
            if secondIsBase, isValidPrefix(first) {
                return CompoundCallsign(baseCall: second, modifier: .prefix(first), text: upper)
            }

            return nil

        default:
            // More than one modifier ("EA4IQL/P/MM") cannot be transmitted.
            return nil
        }
    }

    /// True when `text` is a plain ITU-format callsign with no modifier.
    static func isStandardBaseCall(_ text: String) -> Bool {
        let upper = text.uppercased()
        guard !protocolTokens.contains(upper) else { return false }
        guard !isValidLocator(upper) else { return false }
        guard !isSignalReport(Substring(upper)) else { return false }
        return wholeMatch(baseCallRegex, upper)
    }

    /// A modifier that names the entity operated from: 1–4 characters with at
    /// least one letter, e.g. "I", "EA6", "KH6", "3DA0".
    private static func isValidPrefix(_ text: String) -> Bool {
        guard (1...maxModifierLength).contains(text.count) else { return false }
        guard text.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        return text.contains(where: { $0.isLetter })
    }

    /// A trailing modifier: 1–4 alphanumeric characters. Digits alone are valid
    /// ("K1ABC/1" — operating from another call district).
    private static func isValidSuffix(_ text: String) -> Bool {
        guard (1...maxModifierLength).contains(text.count) else { return false }
        return text.allSatisfy({ $0.isLetter || $0.isNumber })
    }

    // MARK: - Country resolution

    /// The token to feed the country table.
    ///
    /// A prefix modifier always wins: "I/VE6XAD" is worked as Italy, not Canada.
    /// A suffix only changes the country when it is a DXCC prefix rather than an
    /// operating condition, so "VE6XAD/P" stays Canada while "W1AW/VE3" becomes
    /// Canada. Digit suffixes never change the entity.
    var countryLookupToken: String {
        switch modifier {
        case .prefix(let value):
            return value
        case .suffix(let value):
            if Self.operationalSuffixes.contains(value) { return baseCall }
            if value.allSatisfy({ $0.isNumber }) { return baseCall }
            return value
        case nil:
            return baseCall
        }
    }

    // MARK: - Protocol encoding

    /// True when the callsign fits the standard 28-bit FT8 callsign field.
    ///
    /// Only a plain call, or one carrying the protocol's two built-in suffixes
    /// `/P` and `/R`, packs that way. Every other compound call has to travel as
    /// a type-4 (non-standard) message, where it is sent as plain text once and
    /// referred to by a hash afterwards.
    var isStandardPackable: Bool {
        switch modifier {
        case .prefix:
            return false
        case .suffix(let value):
            return value == "P" || value == "R"
        case nil:
            return true
        }
    }

    // MARK: - Decoded text helpers

    /// Unwraps a callsign as it appears in decoded text.
    ///
    /// The decoder prints a hashed callsign in angle brackets: `<VE6XAD>` when it
    /// has already heard the call spelled out, `<...>` when it has not. Returns
    /// the bare callsign, or `nil` when the token is not a usable callsign.
    static func fromDecodedToken(_ token: some StringProtocol) -> CompoundCallsign? {
        var text = String(token)
        if text.hasPrefix("<") && text.hasSuffix(">") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
            // "<...>" is a callsign the decoder has not heard in plain text yet.
            if text == "..." { return nil }
        }
        return parse(text)
    }
}

// MARK: - Base callsign pattern

// 1–3 alphanumeric prefix characters, exactly one digit, 1–3 trailing letters.
// Compiled once: callsigns are validated on every decoded row and on every
// keystroke in the settings fields.
private let baseCallRegex = try! NSRegularExpression(
    pattern: #"^[A-Z0-9]{1,3}\d[A-Z]{1,3}$"#
)

private func wholeMatch(_ regex: NSRegularExpression, _ text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}
