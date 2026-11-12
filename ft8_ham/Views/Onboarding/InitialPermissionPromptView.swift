//
//  InitialPermissionFlowModels.swift
//  ft_ham
//
//  Defines InitialPermissionStep (enum) and LocationPermissionRequester (helper).
//  Permission request screens are embedded inside OnboardingView.
//

import SwiftUI
import CoreLocation

// MARK: - InitialPermissionStep

enum InitialPermissionStep: Int, CaseIterable, Identifiable {
    case location
    case notifications
    case microphone

    var id: Int { rawValue }

    var iconName: String {
        switch self {
        case .location:      return "location.fill"
        case .notifications: return "bell.badge.fill"
        case .microphone:    return "mic.fill"
        }
    }

    var pageColor: Color {
        switch self {
        case .location:      return .blue
        case .notifications: return .orange
        case .microphone:    return .red
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .location:      return "Location Access"
        case .notifications: return "Notifications"
        case .microphone:    return "Microphone Access"
        }
    }

    var bodyText: LocalizedStringKey {
        switch self {
        case .location:
            return "We use your location to calculate your Maidenhead grid automatically and keep your station details accurate."
        case .notifications:
            return "Notifications let you know when RX/TX is paused in the background so you can return to the session quickly."
        case .microphone:
            return "Microphone access is required to decode incoming FT8/FT4 signals and run live RX."
        }
    }

    var impactText: LocalizedStringKey {
        switch self {
        case .location:
            return "Without this you can still enter your grid locator manually in Configuration."
        case .notifications:
            return "Without this, background pause reminders will be disabled."
        case .microphone:
            return "Without this, RX decoding will not work until you grant access in Settings."
        }
    }
}

// MARK: - LocationPermissionRequester

@MainActor
final class LocationPermissionRequester: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        let status = locationManager.authorizationStatus
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Asks for permission when needed, then returns one position fix.
    /// Returns `nil` when access is denied or the fix fails.
    func requestCurrentLocation() async -> CLLocation? {
        let status = await requestWhenInUseAuthorization()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        // A new request replaces one still waiting for a fix.
        if let pending = locationContinuation {
            locationContinuation = nil
            pending.resume(returning: nil)
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation, manager.authorizationStatus != .notDetermined else { return }
        self.continuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locationContinuation else { return }
        self.locationContinuation = nil
        locationContinuation.resume(returning: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationContinuation else { return }
        self.locationContinuation = nil
        locationContinuation.resume(returning: nil)
    }
}
