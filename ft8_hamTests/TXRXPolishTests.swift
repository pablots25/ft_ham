//
//  TXRXPolishTests.swift
//  ft8_hamTests
//
//  Tests for the 1.3.0 TX/RX polish: the Stop QSO tint and one-line status,
//  separate GRID and DXCC badge settings, the first-run Messages Guide, the
//  best-guess waterfall reply and the map opening on the station.
//

import XCTest
import SwiftUI
import MapKit
@testable import ft8_ham

// MARK: - QSO strip

@MainActor
final class QSOStatusViewStyleTests: XCTestCase {

    func testStopQSOIsRedWhileAQSOIsOngoing() {
        XCTAssertEqual(QSOStatusView.stopQSOTint(isQSOOngoing: true), .red)
    }

    func testStopQSOIsSecondaryWhenIdle() {
        XCTAssertEqual(QSOStatusView.stopQSOTint(isQSOOngoing: false), .secondary)
    }

    func testStatusNeverWraps() {
        XCTAssertEqual(QSOStatusView.statusLineLimit, 1)
    }

    /// The old 0.5 floor wrapped "Sending locator to" plus a long compound
    /// call onto a second line on a phone.
    func testStatusShrinksFurtherThanBefore() {
        XCTAssertLessThan(QSOStatusView.statusMinimumScaleFactor, 0.5)
        XCTAssertGreaterThan(QSOStatusView.statusMinimumScaleFactor, 0)
    }
}

// MARK: - Badge settings

@MainActor
final class NeededBadgeSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "NeededBadgeSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testBothBadgesShownWhenBothOn() {
        XCTAssertEqual(NeededBadgeSettings.visible([.grid, .dxcc], showGrid: true, showDXCC: true), [.grid, .dxcc])
    }

    func testGridOffHidesOnlyGrid() {
        XCTAssertEqual(NeededBadgeSettings.visible([.grid, .dxcc], showGrid: false, showDXCC: true), [.dxcc])
    }

    func testDXCCOffHidesOnlyDXCC() {
        XCTAssertEqual(NeededBadgeSettings.visible([.grid, .dxcc], showGrid: true, showDXCC: false), [.grid])
    }

    func testBothOffHidesEverything() {
        XCTAssertEqual(NeededBadgeSettings.visible([.grid, .dxcc], showGrid: false, showDXCC: false), [])
    }

    /// A new callsign is shown by the row tint, never as a badge.
    func testCallsignIsNeverABadge() {
        XCTAssertEqual(NeededBadgeSettings.visible([.callsign], showGrid: true, showDXCC: true), [])
        XCTAssertEqual(NeededBadgeSettings.visible([.callsign, .grid], showGrid: true, showDXCC: true), [.grid])
    }

    func testDefaultIsOnForNewInstalls() {
        XCTAssertTrue(NeededBadgeSettings.legacyDefault(defaults))
    }

    /// Someone who had turned the old shared switch off keeps both badges off.
    func testDefaultFollowsTheOldSharedSwitchWhenOff() {
        defaults.set(false, forKey: NeededBadgeSettings.legacyKey)
        XCTAssertFalse(NeededBadgeSettings.legacyDefault(defaults))
    }

    func testDefaultFollowsTheOldSharedSwitchWhenOn() {
        defaults.set(true, forKey: NeededBadgeSettings.legacyKey)
        XCTAssertTrue(NeededBadgeSettings.legacyDefault(defaults))
    }

    func testSettingKeysAreDistinct() {
        let keys = [NeededBadgeSettings.gridKey, NeededBadgeSettings.dxccKey, NeededBadgeSettings.legacyKey]
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// The Messages Guide shows the short forms used in narrow rows.
    func testShortFormsAreGAndD() {
        XCTAssertEqual(NeededBadgeView.label(for: "GRID", style: .initial), "G")
        XCTAssertEqual(NeededBadgeView.label(for: "DXCC", style: .initial), "D")
        XCTAssertNil(NeededBadgeView.label(for: "GRID", style: .dot))
    }
}

// MARK: - First-run Messages Guide

@MainActor
final class MessagesGuidePromptTests: XCTestCase {

    func testShownOnTXRXTheFirstTime() {
        XCTAssertTrue(MessagesGuidePrompt.shouldPresent(tab: .transmissions, hasSeen: false, isBlocked: false))
    }

    func testNotShownOnceSeen() {
        XCTAssertFalse(MessagesGuidePrompt.shouldPresent(tab: .transmissions, hasSeen: true, isBlocked: false))
    }

    func testNotShownOnOtherTabs() {
        for tab in [AppTab.waterfall, .map, .logbook, .configuration] {
            XCTAssertFalse(MessagesGuidePrompt.shouldPresent(tab: tab, hasSeen: false, isBlocked: false), "\(tab)")
        }
        XCTAssertFalse(MessagesGuidePrompt.shouldPresent(tab: nil, hasSeen: false, isBlocked: false))
    }

    /// Onboarding, the terms, What's New or the settings alert come first.
    func testNotShownWhileSomethingElseIsOnScreen() {
        XCTAssertFalse(MessagesGuidePrompt.shouldPresent(tab: .transmissions, hasSeen: false, isBlocked: true))
    }

    /// Resetting tutorials in Configuration shows the guide again.
    func testResettingTutorialsResetsTheGuide() {
        XCTAssertTrue(AppStorageResetter.tutorialKeys.contains(MessagesGuidePrompt.seenKey))
    }
}

// MARK: - Waterfall best guess

@MainActor
final class WaterfallBestGuessTests: XCTestCase {

    private let ft8Width = WaterfallViewModel.occupiedBandwidthHz(isFT4: false)

    private func placed(_ hz: Double, anchor: Int = 100, span: Int = 190, replyable: Bool = true) -> WaterfallPlacedLabel {
        WaterfallPlacedLabel(
            label: WaterfallLabel(text: replyable ? "CQ" : "TX", frequency: hz, kind: replyable ? .cq : .other),
            anchorRow: anchor,
            spanRows: span
        )
    }

    private func guess(_ labels: [WaterfallPlacedLabel], hz: Double, row: Int = 150,
                       oldestVisibleRow: Int = 0) -> WaterfallPlacedLabel? {
        WaterfallViewModel.bestGuessLabel(
            in: labels, tappedHz: hz, tappedRow: row, oldestVisibleRow: oldestVisibleRow,
            signalWidthHz: ft8Width, isReplyable: { $0.kind == .cq }
        )
    }

    func testTapInsideTheSignalPicksIt() {
        XCTAssertEqual(guess([placed(1000)], hz: 1025)?.label.frequency, 1000)
    }

    /// The old hit test needed the finger within 40 Hz of the base tone.
    func testTapBesideTheLabelStillPicksIt() {
        XCTAssertEqual(guess([placed(1000)], hz: 1120)?.label.frequency, 1000)
        XCTAssertEqual(guess([placed(1000)], hz: 900)?.label.frequency, 1000)
    }

    func testTapFarFromAnySignalPicksNothing() {
        XCTAssertNil(guess([placed(1000)], hz: 1000 + ft8Width + WaterfallViewModel.bestGuessMaxHz + 1))
    }

    func testClosestSignalWins() {
        let labels = [placed(1000), placed(1200)]
        XCTAssertEqual(guess(labels, hz: 1080)?.label.frequency, 1000)
        XCTAssertEqual(guess(labels, hz: 1170)?.label.frequency, 1200)
    }

    /// A label in the tapped slot beats a slightly closer one from another slot.
    func testLabelInTheTappedSlotWins() {
        let sameSlot = placed(1100, anchor: 100, span: 190)
        let otherSlot = placed(1000, anchor: 400, span: 190)
        XCTAssertEqual(guess([sameSlot, otherSlot], hz: 1060, row: 150)?.label.frequency, 1100)
    }

    func testNonReplyableLabelsAreSkipped() {
        let labels = [placed(1000, replyable: false), placed(1100)]
        XCTAssertEqual(guess(labels, hz: 1010)?.label.frequency, 1100)
    }

    func testLabelsScrolledOffScreenAreSkipped() {
        XCTAssertNil(guess([placed(1000, anchor: 100, span: 50)], hz: 1010, oldestVisibleRow: 500))
    }
}

// MARK: - Map opens on the station

@MainActor
final class MapInitialRegionTests: XCTestCase {

    private let home = CLLocationCoordinate2D(latitude: 40.5, longitude: -3.0)   // IN80

    func testCentersOnHomeWithNothingDrawn() {
        let region = MapInitialRegion.region(home: home, content: nil)
        XCTAssertEqual(region.center.latitude, home.latitude, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, home.longitude, accuracy: 1e-9)
        XCTAssertEqual(region.span.latitudeDelta, MapInitialRegion.defaultSpan.latitudeDelta)
    }

    /// Contacts all to the east still leave home in the middle.
    func testStaysCenteredOnHomeWithContactsOnOneSide() {
        let east = MKMapRect(
            origin: MKMapPoint(CLLocationCoordinate2D(latitude: 52, longitude: 10)),
            size: MKMapSize(width: 1, height: 1)
        )
        let region = MapInitialRegion.region(home: home, content: east)
        XCTAssertEqual(region.center.latitude, home.latitude, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, home.longitude, accuracy: 1e-9)
        // Wide enough to reach the contact: twice the distance plus margin.
        XCTAssertGreaterThanOrEqual(region.span.longitudeDelta, 2 * 13)
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, 2 * 11.5)
    }

    func testNeverZoomsInTooFar() {
        let nearby = MKMapRect(origin: MKMapPoint(home), size: MKMapSize(width: 10, height: 10))
        let region = MapInitialRegion.region(home: home, content: nearby)
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, MapInitialRegion.minimumSpan.latitudeDelta)
        XCTAssertGreaterThanOrEqual(region.span.longitudeDelta, MapInitialRegion.minimumSpan.longitudeDelta)
    }

    func testSpanStaysValidForWorldwideContacts() {
        let region = MapInitialRegion.region(home: home, content: .world)
        XCTAssertLessThanOrEqual(region.span.latitudeDelta, 170)
        XCTAssertLessThanOrEqual(region.span.longitudeDelta, 360)
    }

    func testStationLocatorGivesTheHomeCenter() {
        let center = MaidenheadGrid.center(for: "IN80")
        XCTAssertNotNil(center)
        XCTAssertEqual(center?.latitude ?? 0, 40.5, accuracy: 1e-9)
        XCTAssertEqual(center?.longitude ?? 0, -3.0, accuracy: 1e-9)
    }
}
