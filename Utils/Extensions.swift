//
//  Extensions.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 10/11/25.
//

import Foundation
import SwiftUI

// MARK: - Hide keyboard on tap

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - DateFormatter UTC

extension DateFormatter {
    static let utcFormatterMessage: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let utcFormatterClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let utcISOFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" // ISO 8601 with milliseconds
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - rotateLeft

extension Array {
    mutating func rotateLeft(by n: Int) {
        guard n > 0, n < count else { return }
        let slice = self[0 ..< n]
        removeFirst(n)
        append(contentsOf: slice)
    }
}
