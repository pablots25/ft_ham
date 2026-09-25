//
//  RepeatThrottle.swift
//  ft_ham
//
//  Created by Pablo Turrion on 25/09/26.
//

import Foundation

/// Lets the same message through at most once per interval, so a failure
/// that repeats every slot does not flood the screen with identical toasts.
/// Different messages are throttled independently.
struct RepeatThrottle {

    let interval: TimeInterval
    private var lastShown: [String: Date] = [:]

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// True (and records it) when `message` was not let through within the
    /// interval before `now`.
    mutating func shouldShow(_ message: String, at now: Date) -> Bool {
        if let last = lastShown[message], now.timeIntervalSince(last) < interval {
            return false
        }
        lastShown[message] = now
        return true
    }
}
