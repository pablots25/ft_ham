//
//  MapOverlayModelTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 5/10/26.
//

import XCTest
import MapKit
import SwiftUI
@testable import ft8_ham

private func info(_ lat: Double, _ lon: Double, _ name: String = "X") -> CountryInfo {
    CountryInfo(country: name, coordinates: Coordinates(lat: lat, lon: lon))
}

private func heard(_ call: String, snr: Int = -10) -> HeardMeStation {
    HeardMeStation(callsign: call, locator: "JN58", latitude: 48, longitude: 11, bestSNR: snr,
                   lastHeard: Date(timeIntervalSince1970: 0), distanceKm: 1200, reportCount: 1)
}

// MARK: - Layer keys and builders

final class MapOverlayModelTests: XCTestCase {

    func test_gridKeys_dropMalformedAndCaseDuplicates() {
        let keys = MapOverlayModel.gridKeys(for: ["IN80", "in80", "XX", "", "JN58td", "IO91"])
        XCTAssertEqual(keys, ["IN80", "JN58TD", "IO91"])
    }

    func test_gridOverlay_holdsEveryGridInOneMultiPolygon() throws {
        let overlay = try XCTUnwrap(MapOverlayModel.gridOverlay(for: ["IN80", "JN58", "IO91"]))
        XCTAssertEqual(overlay.polygons.count, 3)
        XCTAssertNil(MapOverlayModel.gridOverlay(for: []))
    }

    func test_circleKeys_sameCountryInManyPairsGivesOneCircle() {
        let home = info(40.4, 3.7, "Spain")
        let pairs = [
            CountryPair(sender: home, receiver: info(51.5, 0.1, "England")),
            CountryPair(sender: home, receiver: info(48.8, -2.3, "France")),
            CountryPair(sender: home, receiver: nil),
            CountryPair(sender: info(51.5, 0.1, "England"), receiver: home)
        ]
        XCTAssertEqual(MapOverlayModel.circleKeys(for: pairs).count, 3)
    }

    func test_segmentKeys_ignoreDirectionAndMissingReceiver() {
        let a = info(40.4, 3.7), b = info(51.5, 0.1)
        let pairs = [
            CountryPair(sender: a, receiver: b),
            CountryPair(sender: b, receiver: a),
            CountryPair(sender: a, receiver: nil),
            CountryPair(sender: a, receiver: a)
        ]
        XCTAssertEqual(MapOverlayModel.segmentKeys(for: pairs).count, 1)
    }

    func test_geodesicOverlay_isOneMultiPolyline() throws {
        let pairs = [
            CountryPair(sender: info(40.4, 3.7), receiver: info(51.5, 0.1)),
            CountryPair(sender: info(40.4, 3.7), receiver: info(35.6, -139.7))
        ]
        let overlay = try XCTUnwrap(MapOverlayModel.geodesicOverlay(for: MapOverlayModel.segmentKeys(for: pairs)))
        XCTAssertEqual(overlay.polylines.count, 2)
        XCTAssertTrue(overlay.polylines.allSatisfy { $0 is MKGeodesicPolyline })
    }

    func test_circlePolygon_matchesMKCircleBounds() {
        let center = CLLocationCoordinate2D(latitude: 40.4, longitude: -3.7)
        let ring = MapOverlayModel.circlePolygon(center: center, radius: 150_000, segments: 256)
        let circle = MKCircle(center: center, radius: 150_000)
        XCTAssertEqual(ring.pointCount, 256)
        XCTAssertEqual(ring.boundingMapRect.width, circle.boundingMapRect.width, accuracy: circle.boundingMapRect.width * 0.01)
        XCTAssertEqual(ring.boundingMapRect.midX, circle.boundingMapRect.midX, accuracy: circle.boundingMapRect.width * 0.01)
    }
}

// MARK: - Annotation diff

final class MapAnnotationDiffTests: XCTestCase {

    func test_diff_reportsOnlyAddedAndRemovedKeys() {
        let current: Set<MapAnnotationKey> = [.grid("IN80"), .grid("JN58"), .heardMe(heard("DL1ABC"))]
        let diff = MapAnnotationDiff(current: current, desired: [.grid("IN80"), .grid("IO91"), .heardMe(heard("DL1ABC"))])
        XCTAssertEqual(diff.added, [.grid("IO91")])
        XCTAssertEqual(diff.removed, [.grid("JN58")])
    }

    func test_diff_unchangedSetIsEmpty() {
        let keys: [MapAnnotationKey] = [.grid("IN80"), .heardMe(heard("DL1ABC"))]
        XCTAssertTrue(MapAnnotationDiff(current: Set(keys), desired: keys).isEmpty)
    }

    func test_diff_changedStationReplacesItsMarker() {
        let diff = MapAnnotationDiff(current: [.heardMe(heard("DL1ABC", snr: -10))],
                                     desired: [.heardMe(heard("DL1ABC", snr: -3))])
        XCTAssertEqual(diff.added, [.heardMe(heard("DL1ABC", snr: -3))])
        XCTAssertEqual(diff.removed, [.heardMe(heard("DL1ABC", snr: -10))])
    }

    func test_diff_duplicateDesiredKeysAreAddedOnce() {
        let diff = MapAnnotationDiff(current: [], desired: [.grid("IN80"), .grid("IN80")])
        XCTAssertEqual(diff.added, [.grid("IN80")])
    }
}

// MARK: - Coordinator incremental updates

@MainActor
final class GridMapCoordinatorIncrementalTests: XCTestCase {

    private func makeCoordinator() -> GridMapView.Coordinator {
        var mode: MKUserTrackingMode = .none
        return GridMapView.Coordinator(onUserLocator: nil,
                                       trackingMode: Binding(get: { mode }, set: { mode = $0 }))
    }

    private let allOn = MapVisibility(grids: true, countryCircles: true, geodesics: true, annotations: true)

    func test_layersStayOneOverlayEachAsDataGrows() {
        let mapView = MKMapView()
        let coordinator = makeCoordinator()
        let pairs = [CountryPair(sender: info(40.4, 3.7), receiver: info(51.5, 0.1))]
        coordinator.updateMap(mapView, locators: ["IN80"], countries: pairs, visibility: allOn)
        coordinator.updateMap(mapView, locators: ["IN80", "JN58", "IO91"], countries: pairs, visibility: allOn)
        XCTAssertEqual(mapView.overlays.count, 3)
    }

    func test_addingLocatorKeepsOtherLayersAndExistingLabels() throws {
        let mapView = MKMapView()
        let coordinator = makeCoordinator()
        let pairs = [CountryPair(sender: info(40.4, 3.7), receiver: info(51.5, 0.1))]
        coordinator.updateMap(mapView, locators: ["IN80"], countries: pairs, visibility: allOn)
        let circles = try XCTUnwrap(mapView.overlays.first { $0 is MKMultiPolygon && ($0 as! MKMultiPolygon).polygons.count == 2 })
        let label = try XCTUnwrap(mapView.annotations.first { $0.title == "IN80" })

        coordinator.updateMap(mapView, locators: ["IN80", "JN58"], countries: pairs, visibility: allOn)

        XCTAssertTrue(mapView.overlays.contains { $0 === circles }, "circle layer must not be rebuilt")
        XCTAssertTrue(mapView.annotations.contains { $0 === label }, "existing label must not be re-added")
        XCTAssertEqual(mapView.annotations.filter { $0 is GridLabelAnnotation }.count, 2)
    }

    func test_turningGeodesicsOffRemovesOnlyThatLayer() {
        let mapView = MKMapView()
        let coordinator = makeCoordinator()
        let pairs = [CountryPair(sender: info(40.4, 3.7), receiver: info(51.5, 0.1))]
        coordinator.updateMap(mapView, locators: ["IN80"], countries: pairs, visibility: allOn)
        let off = MapVisibility(grids: true, countryCircles: true, geodesics: false, annotations: true)
        coordinator.updateMap(mapView, locators: ["IN80"], countries: pairs, visibility: off)
        XCTAssertFalse(mapView.overlays.contains { $0 is MKMultiPolyline })
        XCTAssertEqual(mapView.overlays.count, 2)
    }

    func test_resetClearsGridsAndLabels() {
        let mapView = MKMapView()
        let coordinator = makeCoordinator()
        coordinator.updateMap(mapView, locators: ["IN80", "JN58"], countries: [], visibility: allOn)
        coordinator.updateMap(mapView, locators: [], countries: [], visibility: allOn)
        XCTAssertTrue(mapView.overlays.isEmpty)
        XCTAssertTrue(mapView.annotations.filter { !($0 is MKUserLocation) }.isEmpty)
    }

    func test_geodesicsStayAboveGridsAfterGridLayerIsRebuilt() {
        let mapView = MKMapView()
        let coordinator = makeCoordinator()
        let pairs = [CountryPair(sender: info(40.4, 3.7), receiver: info(51.5, 0.1))]
        coordinator.updateMap(mapView, locators: ["IN80"], countries: pairs, visibility: allOn)
        coordinator.updateMap(mapView, locators: ["IN80", "JN58"], countries: pairs, visibility: allOn)
        XCTAssertTrue(mapView.overlays.last is MKMultiPolyline)
    }
}
