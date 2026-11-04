//
//  FreeTextMessage.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation

/// Rules for FT8/FT4 free-text (type 0.0) messages.
///
/// The protocol packs up to 13 characters from a 42-symbol alphabet into the
/// 71-bit payload; anything else has to be dropped before encoding.
enum FreeTextMessage {
    static let maxLength = 13
    static let alphabet: Set<Character> = Set(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ+-./?")

    enum ValidationError: Error, Equatable {
        case empty
        case tooLong
        case invalidCharacter(Character)
    }

    /// Uppercases, drops characters outside the alphabet, collapses runs of
    /// spaces, trims, and cuts to 13 characters. Used live while typing.
    static func sanitize(_ raw: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in raw.uppercased() where alphabet.contains(ch) {
            if ch == " " {
                if lastWasSpace || out.isEmpty { continue }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
            out.append(ch)
            if out.count == maxLength { break }
        }
        while out.last == " " { out.removeLast() }
        return out
    }

    /// Strict check for text that is about to go on the air.
    static func validate(_ text: String) -> Result<String, ValidationError> {
        if text.isEmpty { return .failure(.empty) }
        if text.count > maxLength { return .failure(.tooLong) }
        if let bad = text.first(where: { !alphabet.contains($0) }) {
            return .failure(.invalidCharacter(bad))
        }
        return .success(text)
    }
}
