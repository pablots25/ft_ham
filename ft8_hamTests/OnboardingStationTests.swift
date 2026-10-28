//
//  OnboardingStationTests.swift
//  ft8_hamTests
//
//  The onboarding station step writes the callsign and locator straight to
//  UserDefaults through @AppStorage. The view model must still notice, or the
//  "Callsign and Locator not configured" launch alert would show anyway.
//

import Combine
import XCTest
@testable import ft8_ham

@MainActor
final class OnboardingStationTests: XCTestCase {

    private let keys = ["callsign", "locator"]
    private var viewModel: FT8ViewModel!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        // Start from an explicitly empty station: a removed key can fall
        // through to settings stored outside the app container (see TestDefaults).
        keys.forEach { UserDefaults.standard.set("", forKey: $0) }
        // Keep the GPS auto-locator from filling the empty locator with the
        // simulator's location, which would make the station valid.
        UserDefaults.standard.set(false, forKey: "autoLocatorFromGPS")
        viewModel = FT8ViewModel(txMessages: [], rxMessages: [])
    }

    override func tearDown() async throws {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: "autoLocatorFromGPS")
        cancellables.removeAll()
        viewModel = nil
        try await super.tearDown()
    }

    func test_directDefaultsWrite_marksSettingsLoaded() async {
        XCTAssertFalse(viewModel.rootState.settingsLoaded)

        let loaded = expectation(description: "settingsLoaded becomes true")
        viewModel.rootState.$settingsLoaded
            .filter { $0 }
            .first()
            .sink { _ in loaded.fulfill() }
            .store(in: &cancellables)

        UserDefaults.standard.set("EA1AAA", forKey: "callsign")
        UserDefaults.standard.set("IN70", forKey: "locator")

        await fulfillment(of: [loaded], timeout: 2)
        XCTAssertTrue(viewModel.settingsLoaded)
    }

    func test_invalidStationFromDefaults_keepsSettingsUnloaded() async throws {
        UserDefaults.standard.set("EA1AAA", forKey: "callsign")
        UserDefaults.standard.set("", forKey: "locator")

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(viewModel.rootState.settingsLoaded)
    }
}
