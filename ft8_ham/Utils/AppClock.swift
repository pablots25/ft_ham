//
//  AppClock.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import os

/// Wall clock corrected by the SNTP offset measured by `ClockSyncManager`.
///
/// FT8/FT4 slots are 15 s / 7.5 s wide and decoders tolerate about ±2 s of
/// misalignment, so a device clock a couple of seconds off silently kills
/// every QSO. Everything that derives slot boundaries or stamps decodes
/// reads `AppClock.now()` instead of `Date()`.
final class AppClock: @unchecked Sendable {
    static let shared = AppClock()

    private let storage = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

    /// Seconds to add to the system clock to obtain true UTC (`true - system`).
    var offset: TimeInterval {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// Corrected current time.
    static func now() -> Date {
        Date().addingTimeInterval(shared.offset)
    }

    /// Applies the current offset to a raw system-clock date.
    static func corrected(_ systemDate: Date) -> Date {
        systemDate.addingTimeInterval(shared.offset)
    }
}
