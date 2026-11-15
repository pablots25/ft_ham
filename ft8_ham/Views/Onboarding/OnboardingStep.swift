//
//  OnboardingStep.swift
//  ft_ham
//
//  The four steps of the first-run onboarding, kept free of UI so the order
//  and the station check can be unit tested.
//

import Foundation

/// The steps of the onboarding, in the order they are shown.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    /// Highlights and acceptance of the Terms of Use and Privacy Policy.
    case welcome
    /// Callsign and locator.
    case station
    /// What You Need, plus the microphone permission.
    case audio
    /// Setup checklist and the first RX start.
    case ready

    var id: Int { rawValue }

    /// The step after this one, or `nil` on the last step.
    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var isLast: Bool { next == nil }

    /// 1-based position, used by the "Step 2 of 4" indicator.
    var number: Int { rawValue + 1 }

    static var count: Int { allCases.count }
}

/// How the operator left the onboarding.
enum OnboardingExit: Equatable {
    /// Start RX right away and show the TX/RX tab.
    case startReceiving
    /// Close the onboarding and show the TX/RX tab without starting RX.
    case explore
}

enum OnboardingStation {
    /// True when RX can start with these values. Mirrors
    /// `FT8ViewModel.settingsLoaded`, which `startSequencer()` requires.
    static func isReady(callsign: String, locator: String) -> Bool {
        !callsign.isEmpty && isValidCallsign(callsign)
            && !locator.isEmpty && isValidLocator(locator)
    }

    /// The 4-character locator for a GPS position, as the station settings
    /// store it.
    static func locator(latitude: Double, longitude: Double) -> String? {
        guard (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else { return nil }
        // The north pole and the antimeridian sit on the upper edge of the
        // last field. Pull them just inside so the letters stay within A-R.
        let lat = min(latitude, 89.999_999)
        let lon = min(longitude, 179.999_999)
        let grid = MaidenheadGrid.locator(latitude: lat, longitude: lon, precision: 4)
        return isValidLocator(grid) ? grid : nil
    }
}
