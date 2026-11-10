//
//  WhatsNewPolicyTests.swift
//  ft8_hamTests
//

import XCTest
@testable import ft8_ham

private typealias Settings = WhatsNewConfig.WhatsNewSettings
private typealias Item = WhatsNewConfig.WhatsNewSettings.WhatsNewItem

private func settings(
    enabled: Bool = true,
    features: [Item] = [],
    improvements: [Item] = [],
    bugFixes: [Item] = []
) -> Settings {
    Settings(enabled: enabled, features: features, improvements: improvements, bugFixes: bugFixes)
}

private let plainItem = Item(id: "plain", title: "Plain", description: "No flag")
private let freeTextItem = Item(id: "freetext", title: "Free text", description: "Gated",
                                flag: FeatureFlag.enableFreeText.rawValue)
private let heardMeItem = Item(id: "heardme", title: "Heard me", description: "Gated",
                               flag: FeatureFlag.enableHeardMe.rawValue)

// MARK: - Policy

final class WhatsNewPolicyTests: XCTestCase {

    func test_decoding_withoutFlagKey_leavesFlagNil() throws {
        let json = #"{"whatsNew":{"enabled":true,"features":[{"id":"a","title":"A","description":"d"}],"improvements":[],"bugFixes":[]}}"#
        let config = try JSONDecoder().decode(WhatsNewConfig.self, from: Data(json.utf8))
        XCTAssertNil(config.whatsNew.features.first?.flag)
    }

    func test_decoding_withFlagKey_readsFlag() throws {
        let json = #"{"whatsNew":{"enabled":true,"features":[{"id":"a","title":"A","description":"d","flag":"enableHeardMe"}],"improvements":[],"bugFixes":[]}}"#
        let config = try JSONDecoder().decode(WhatsNewConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.whatsNew.features.first?.flag, "enableHeardMe")
    }

    func test_visible_hidesItemsWhoseFlagIsOff() {
        let result = WhatsNewPolicy.visible(
            settings(features: [plainItem, freeTextItem, heardMeItem]),
            isEnabled: { $0 == .enableHeardMe }
        )
        XCTAssertEqual(result.features.map(\.id), ["plain", "heardme"])
    }

    func test_visible_hidesItemsWithUnknownFlag() {
        let unknown = Item(id: "future", title: "F", description: "d", flag: "flagFromNewerBuild")
        let result = WhatsNewPolicy.visible(settings(improvements: [unknown]), isEnabled: { _ in true })
        XCTAssertTrue(result.improvements.isEmpty)
    }

    func test_trigger_isNilWhenDisabled() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(enabled: false, features: [plainItem]),
            currentVersion: "1.4", lastSeenVersion: "1.3",
            seenFlaggedIDs: [], isEnabled: { _ in true }
        )
        XCTAssertNil(trigger)
    }

    func test_trigger_isNilWithoutBaselineVersion() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(features: [plainItem]),
            currentVersion: "1.4", lastSeenVersion: "",
            seenFlaggedIDs: [], isEnabled: { _ in true }
        )
        XCTAssertNil(trigger)
    }

    func test_trigger_versionBumpOnMinorUpdate() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(features: [plainItem]),
            currentVersion: "1.4.0", lastSeenVersion: "1.3.2",
            seenFlaggedIDs: [], isEnabled: { _ in false }
        )
        XCTAssertEqual(trigger, .versionBump)
    }

    func test_trigger_ignoresPatchUpdateWithOnlyPlainItems() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(features: [plainItem]),
            currentVersion: "1.3.2", lastSeenVersion: "1.3.1",
            seenFlaggedIDs: [], isEnabled: { _ in true }
        )
        XCTAssertNil(trigger)
    }

    func test_trigger_isNilOnBumpWhenEveryItemIsHidden() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(features: [freeTextItem]),
            currentVersion: "1.4", lastSeenVersion: "1.3",
            seenFlaggedIDs: [], isEnabled: { _ in false }
        )
        XCTAssertNil(trigger)
    }

    func test_trigger_announcesFlagTurnedOnMidVersion() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(features: [plainItem, heardMeItem]),
            currentVersion: "1.4.1", lastSeenVersion: "1.4.0",
            seenFlaggedIDs: [], isEnabled: { $0 == .enableHeardMe }
        )
        XCTAssertEqual(trigger, .newFeatures(ids: ["heardme"]))
    }

    func test_trigger_doesNotRepeatSeenFlaggedItem() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(features: [heardMeItem]),
            currentVersion: "1.4", lastSeenVersion: "1.4",
            seenFlaggedIDs: ["heardme"], isEnabled: { _ in true }
        )
        XCTAssertNil(trigger)
    }

    func test_trigger_staysQuietWhileFlagIsOff() {
        let trigger = WhatsNewPolicy.trigger(
            settings: settings(features: [heardMeItem]),
            currentVersion: "1.4", lastSeenVersion: "1.4",
            seenFlaggedIDs: [], isEnabled: { _ in false }
        )
        XCTAssertNil(trigger)
    }

    func test_majorMinorBump() {
        XCTAssertTrue(WhatsNewPolicy.isMajorOrMinorBump(from: "1.3.2", to: "1.4.0"))
        XCTAssertTrue(WhatsNewPolicy.isMajorOrMinorBump(from: "1.9", to: "2.0"))
        XCTAssertFalse(WhatsNewPolicy.isMajorOrMinorBump(from: "1.4.0", to: "1.4.3"))
        XCTAssertFalse(WhatsNewPolicy.isMajorOrMinorBump(from: "2.0", to: "1.9"))
        XCTAssertTrue(WhatsNewPolicy.isMajorOrMinorBump(from: "beta", to: "gamma"))
    }
}

// MARK: - Manager (persistence)

@MainActor
final class AppVersionManagerWhatsNewTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var version = "1.4.0"
    private var config = settings(features: [plainItem, heardMeItem])
    private var enabledFlags: Set<FeatureFlag> = []

    override func setUp() {
        super.setUp()
        suiteName = "WhatsNewTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        version = "1.4.0"
        config = settings(features: [plainItem, heardMeItem])
        enabledFlags = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeManager() -> AppVersionManager {
        AppVersionManager(
            defaults: defaults,
            shortVersion: { [unowned self] in self.version },
            settings: { [unowned self] in self.config },
            isEnabled: { [unowned self] in self.enabledFlags.contains($0) }
        )
    }

    func test_freshInstall_recordsBaselineAndStaysQuiet() {
        let manager = makeManager()
        XCTAssertFalse(manager.shouldShowWhatsNew)

        manager.recordInstallBaselineIfNeeded()

        XCTAssertEqual(defaults.string(forKey: AppVersionManager.Keys.lastSeenAppVersion), "1.4.0")
        XCTAssertFalse(manager.shouldShowWhatsNew)
    }

    func test_freshInstall_thenMinorUpdate_showsWhatsNew() {
        let manager = makeManager()
        manager.recordInstallBaselineIfNeeded()

        version = "1.5.0"

        XCTAssertEqual(manager.whatsNewTrigger, .versionBump)
    }

    func test_baseline_marksAlreadyEnabledFeaturesAsSeen() {
        enabledFlags = [.enableHeardMe]
        let manager = makeManager()
        manager.recordInstallBaselineIfNeeded()

        XCTAssertFalse(manager.shouldShowWhatsNew)
    }

    func test_baseline_doesNotOverwriteExistingVersion() {
        defaults.set("1.2.0", forKey: AppVersionManager.Keys.lastSeenAppVersion)
        let manager = makeManager()

        manager.recordInstallBaselineIfNeeded()

        XCTAssertEqual(defaults.string(forKey: AppVersionManager.Keys.lastSeenAppVersion), "1.2.0")
        XCTAssertEqual(manager.whatsNewTrigger, .versionBump)
    }

    func test_flagTurnedOn_showsOnlyThatFeature_thenNotAgain() {
        let manager = makeManager()
        manager.recordInstallBaselineIfNeeded()
        XCTAssertFalse(manager.shouldShowWhatsNew)

        enabledFlags = [.enableHeardMe]

        XCTAssertEqual(manager.whatsNewTrigger, .newFeatures(ids: ["heardme"]))
        XCTAssertEqual(manager.whatsNewContent?.features.map(\.id), ["heardme"])

        manager.markWhatsNewAsViewed()

        XCTAssertFalse(manager.shouldShowWhatsNew)
    }

    func test_versionBumpContent_listsEveryVisibleItem() {
        defaults.set("1.3.0", forKey: AppVersionManager.Keys.lastSeenAppVersion)
        enabledFlags = [.enableHeardMe]
        let manager = makeManager()

        XCTAssertEqual(manager.whatsNewContent?.features.map(\.id), ["plain", "heardme"])
    }

    func test_viewingOnBump_alsoMarksFlaggedItemsSeen() {
        defaults.set("1.3.0", forKey: AppVersionManager.Keys.lastSeenAppVersion)
        enabledFlags = [.enableHeardMe]
        let manager = makeManager()

        manager.markWhatsNewAsViewed()

        XCTAssertFalse(manager.shouldShowWhatsNew)
        XCTAssertEqual(defaults.stringArray(forKey: AppVersionManager.Keys.seenFlaggedItemIDs), ["heardme"])
    }

    func test_content_isNilWhenDisabled() {
        config = settings(enabled: false, features: [plainItem])
        XCTAssertNil(makeManager().whatsNewContent)
    }
}
