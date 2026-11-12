//
//  MacPlatform.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/11/26.
//

import Foundation

/// Facts about the platform the app runs on. The app ships to the Mac as
/// "Designed for iPad", where `userInterfaceIdiom` reports `.pad`, so the
/// idiom alone cannot tell a Mac from an iPad.
enum RunningPlatform {
    /// `true` when the iPad build runs on a Mac with Apple silicon.
    static var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }
}

/// Decides whether reception and transmission keep going while the app is in
/// the background.
///
/// On iPhone and iPad the system suspends a backgrounded app, so the
/// sequencer is stopped on purpose. On a Mac the process keeps running when
/// its window is hidden (Cmd+H) or minimized, and operators expect a QSO to
/// carry on, as it does in desktop FT8 software.
enum BackgroundOperationPolicy {
    static func keepsRadioRunning(isMac: Bool, flagEnabled: Bool) -> Bool {
        isMac && flagEnabled
    }

    /// The policy for this device and the current feature flag.
    @MainActor
    static var current: Bool {
        keepsRadioRunning(
            isMac: RunningPlatform.isMac,
            flagEnabled: FeatureFlagManager.shared.isEnabled(.macBackgroundOperation)
        )
    }
}
