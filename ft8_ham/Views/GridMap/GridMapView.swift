//
//  GridMapView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 23/11/25.
//

import MapKit
import SwiftUI
import CoreLocation

// MARK: - Map Visibility Settings

struct MapVisibility: Hashable {
    let grids: Bool
    let countryCircles: Bool
    let geodesics: Bool
    let annotations: Bool
    var heardMe: Bool = true
    var presence: Bool = true
}

/// Label for a worked grid square, drawn as a blue marker.
final class GridLabelAnnotation: NSObject, MKAnnotation {
    let locator: String
    let coordinate: CLLocationCoordinate2D
    var title: String? { locator }
    init?(locator: String) {
        guard let center = MaidenheadGrid.center(for: locator) else { return nil }
        self.locator = locator
        self.coordinate = center
    }
}

/// A receiver that heard us (PSK Reporter), drawn as an orange marker.
final class HeardMeAnnotation: NSObject, MKAnnotation {
    let station: HeardMeStation
    var coordinate: CLLocationCoordinate2D { station.coordinate }
    var title: String? { station.callsign }
    var subtitle: String? {
        var parts: [String] = []
        if let snr = station.bestSNR { parts.append(String(format: "%+d dB", snr)) }
        if let km = station.distanceKm { parts.append("\(Int(km.rounded())) km") }
        return parts.joined(separator: " · ")
    }
    init(station: HeardMeStation) { self.station = station }
}

/// Another FT Ham operator currently on the air, drawn as a cyan marker.
final class PresenceAnnotation: NSObject, MKAnnotation {
    let station: PresenceStation
    let coordinate: CLLocationCoordinate2D
    var title: String? { station.callsign }
    var subtitle: String? {
        let where_ = [station.band, station.mode].filter { !$0.isEmpty }.joined(separator: " ")
        let minutes = max(0, Int(Date().timeIntervalSince(station.lastSeen) / 60))
        return where_.isEmpty ? "\(minutes) min" : "\(where_) · \(minutes) min"
    }
    init?(station: PresenceStation) {
        guard let center = MaidenheadGrid.center(for: station.grid) else { return nil }
        self.station = station
        self.coordinate = center
    }
}

// MARK: - Map View with grids, countries, routes, and user location

struct GridMapView: UIViewRepresentable {

    /// Maidenhead locators to be displayed (including user grid)
    var locators: [String]

    /// Optional list of country pairs
    var countries: [CountryPair] = []

    /// Optional route points
    var routePoints: [CLLocationCoordinate2D] = []

    /// Stations that heard us, from PSK Reporter.
    var heardMeStations: [HeardMeStation] = []
    /// Other FT Ham operators on the air (opt-in presence map).
    var presenceStations: [PresenceStation] = []

    var showGrids: Bool = true
    var showCountryCircles: Bool = true
    var showGeodesics: Bool = true
    var showAnnotations: Bool = true
    var showHeardMe: Bool = true
    var showPresence: Bool = true
    /// When false (map tab not selected) data changes are not applied; the
    /// latest data is applied once the map becomes active again.
    var isActive: Bool = true
    @Binding var userTrackingMode: MKUserTrackingMode
    /// Invoked (on the main actor) when the device location resolves to a grid
    /// square that is not yet in `locators`.
    var onUserLocator: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onUserLocator: onUserLocator, trackingMode: $userTrackingMode)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.attachMapView(mapView)

        // Flat terrain: tilting the map does not pay for 3D elevation.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration

        mapView.showsCompass = false   // replaced by positioned MKCompassButton below
        mapView.showsScale = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isUserInteractionEnabled = true
        mapView.showsUserLocation = context.coordinator.canShowUserLocation
        if #available(iOS 17.0, *) {
            mapView.pitchButtonVisibility = .adaptive
        }

        context.coordinator.configureLocationManager()

        // MARK: - Native map buttons

        // Compass only — tracking is handled by the SwiftUI toolbar button via userTrackingMode binding
        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .adaptive
        compass.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(compass)

        NSLayoutConstraint.activate([
            compass.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 8),
            compass.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -12)
        ])

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.userTrackingMode != userTrackingMode {
            uiView.setUserTrackingMode(userTrackingMode, animated: true)
        }
        guard isActive else { return }
        let visibility = MapVisibility(
            grids: showGrids,
            countryCircles: showCountryCircles,
            geodesics: showGeodesics,
            annotations: showAnnotations,
            heardMe: showHeardMe,
            presence: showPresence
        )
        context.coordinator.updateMap(
            uiView, locators: locators, countries: countries,
            heardMe: heardMeStations, presence: presenceStations, visibility: visibility
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {

        /// Everything `updateMap` draws from. Arrays compare by storage
        /// identity first, so an unchanged input costs almost nothing.
        private struct Inputs: Equatable {
            let locators: [String]
            let countries: [CountryPair]
            let heardMe: [HeardMeStation]
            let presence: [PresenceStation]
            let visibility: MapVisibility
        }

        // Callbacks / bindings
        private let onUserLocator: ((String) -> Void)?
        private let trackingModeBinding: Binding<MKUserTrackingMode>
        private var knownLocators: Set<String> = []

        // Location: the manager only handles authorization; positions come
        // from MapKit's own user-location tracking.
        private let locationManager = CLLocationManager()
        private var lastUserLocator: String?
        private weak var mapView: MKMapView?

        // One overlay per layer, each rebuilt only when its keys change.
        private var lastInputs: Inputs?
        private var gridKeys: [String] = []
        private var circleKeys: [MapOverlayModel.PointKey] = []
        private var segmentKeys: [MapOverlayModel.SegmentKey] = []
        private var gridOverlay: MKMultiPolygon?
        private var circleOverlay: MKMultiPolygon?
        private var geodesicOverlay: MKMultiPolyline?
        private var annotationsByKey: [MapAnnotationKey: MKAnnotation] = [:]

        private var hasEverFitRegion = false

        init(onUserLocator: ((String) -> Void)?, trackingMode: Binding<MKUserTrackingMode>) {
            self.onUserLocator = onUserLocator
            self.trackingModeBinding = trackingMode
            super.init()
            locationManager.delegate = self
        }

        // MARK: - Location handling

        var canShowUserLocation: Bool {
            switch locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                return true
            default:
                return false
            }
        }

        func configureLocationManager() {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }

        func attachMapView(_ mapView: MKMapView) {
            self.mapView = mapView
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard let mapView else { return }

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                mapView.showsUserLocation = true
            case .denied, .restricted:
                mapView.showsUserLocation = false
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location else { return }

            let locator = MaidenheadGrid.locator(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                precision: 4
            )

            // Avoid unnecessary updates
            guard locator != lastUserLocator else { return }
            lastUserLocator = locator

            Task { @MainActor in
                if !self.knownLocators.contains(locator) {
                    self.onUserLocator?(locator)
                }

                if mapView.userTrackingMode == .follow || mapView.userTrackingMode == .followWithHeading {
                    self.zoomToGridSquare(locator: locator, on: mapView, animated: true)
                }
            }
        }

        // MARK: - Map update

        @MainActor
        func updateMap(_ mapView: MKMapView, locators: [String], countries: [CountryPair],
                       heardMe: [HeardMeStation] = [], presence: [PresenceStation] = [],
                       visibility: MapVisibility) {
            let inputs = Inputs(locators: locators, countries: countries,
                                heardMe: heardMe, presence: presence, visibility: visibility)
            guard inputs != lastInputs else { return }
            lastInputs = inputs
            knownLocators = Set(locators)

            let grids = visibility.grids ? MapOverlayModel.gridKeys(for: locators) : []
            if grids != gridKeys {
                gridKeys = grids
                let old = gridOverlay
                gridOverlay = MapOverlayModel.gridOverlay(for: grids)
                install(gridOverlay, replacing: old, rank: 0, on: mapView)
            }

            let circles = visibility.countryCircles ? MapOverlayModel.circleKeys(for: countries) : []
            if circles != circleKeys {
                circleKeys = circles
                let old = circleOverlay
                circleOverlay = MapOverlayModel.circleOverlay(for: circles)
                install(circleOverlay, replacing: old, rank: 1, on: mapView)
            }

            let segments = visibility.geodesics ? MapOverlayModel.segmentKeys(for: countries) : []
            if segments != segmentKeys {
                segmentKeys = segments
                let old = geodesicOverlay
                geodesicOverlay = MapOverlayModel.geodesicOverlay(for: segments)
                install(geodesicOverlay, replacing: old, rank: 2, on: mapView)
            }

            // The grid-label toggle only governs locator labels; heard-me and
            // presence markers have their own switches.
            var desired: [MapAnnotationKey] = []
            if visibility.annotations {
                desired += grids.map(MapAnnotationKey.grid)
            }
            if visibility.heardMe {
                desired += heardMe.map(MapAnnotationKey.heardMe)
            }
            if visibility.presence {
                desired += presence.map(MapAnnotationKey.presence)
            }
            applyAnnotations(MapAnnotationDiff(current: Set(annotationsByKey.keys), desired: desired), on: mapView)

            let layers: [MKOverlay] = [gridOverlay, circleOverlay, geodesicOverlay].compactMap { $0 }
            if !hasEverFitRegion && !layers.isEmpty {
                fitAll(mapView, overlays: layers)
            }
        }

        // MARK: - Helper Methods

        /// Swaps one layer's overlay, keeping layers stacked grids → circles → geodesics.
        private func install(_ overlay: MKOverlay?, replacing old: MKOverlay?, rank: Int, on mapView: MKMapView) {
            if let old { mapView.removeOverlay(old) }
            guard let overlay else { return }
            let layers: [MKOverlay?] = [gridOverlay, circleOverlay, geodesicOverlay]
            if let below = layers[..<rank].compactMap({ $0 }).last {
                mapView.insertOverlay(overlay, above: below)
            } else {
                mapView.insertOverlay(overlay, at: 0, level: .aboveLabels)
            }
        }

        private func applyAnnotations(_ diff: MapAnnotationDiff, on mapView: MKMapView) {
            guard !diff.isEmpty else { return }
            let gone = diff.removed.compactMap { annotationsByKey.removeValue(forKey: $0) }
            if !gone.isEmpty { mapView.removeAnnotations(gone) }

            var added: [MKAnnotation] = []
            for key in diff.added {
                guard let annotation = makeAnnotation(for: key) else { continue }
                annotationsByKey[key] = annotation
                added.append(annotation)
            }
            if !added.isEmpty { mapView.addAnnotations(added) }
        }

        private func makeAnnotation(for key: MapAnnotationKey) -> MKAnnotation? {
            switch key {
            case .grid(let locator): return GridLabelAnnotation(locator: locator)
            case .heardMe(let station): return HeardMeAnnotation(station: station)
            case .presence(let station): return PresenceAnnotation(station: station)
            }
        }

        // MARK: - Renderers

        func mapView(_ mapView: MKMapView,
                     rendererFor overlay: MKOverlay) -> MKOverlayRenderer {

            switch overlay {
            case let multiPolygon as MKMultiPolygon:
                let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
                if multiPolygon === circleOverlay {
                    renderer.strokeColor = .systemGreen
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.15)
                    renderer.lineWidth = 2
                } else {
                    renderer.strokeColor = .systemRed
                    renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.2)
                    renderer.lineWidth = 1.5
                }
                return renderer

            case let multiPolyline as MKMultiPolyline:
                let renderer = MKMultiPolylineRenderer(multiPolyline: multiPolyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 3
                renderer.alpha = 0.8
                return renderer

            case let polygon as MKPolygon:
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = .systemRed
                renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.2)
                renderer.lineWidth = 1.5
                return renderer

            case let circle as MKCircle:
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = .systemGreen
                renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.15)
                renderer.lineWidth = 2
                return renderer

            case let polyline as MKPolyline:
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = polyline is MKGeodesicPolyline ? .systemBlue : .gray
                renderer.lineWidth = polyline is MKGeodesicPolyline ? 3 : 1
                renderer.alpha = 0.8
                return renderer

            default:
                return MKOverlayRenderer(overlay: overlay)
            }
        }

        func mapView(_ mapView: MKMapView,
                     viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                let id = "cluster"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = cluster
                view.glyphImage = nil
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.markerTintColor = Self.tint(for: cluster.memberAnnotations.first)
                view.canShowCallout = false
                return view
            }

            if annotation is PresenceAnnotation {
                let id = "presence"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.glyphImage = UIImage(systemName: "person.fill")
                view.glyphText = nil
                view.markerTintColor = .systemCyan
                view.clusteringIdentifier = "presence"
                view.displayPriority = .defaultLow
                view.canShowCallout = true
                return view
            }

            if annotation is HeardMeAnnotation {
                let id = "heardMe"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.glyphImage = UIImage(systemName: "ear")
                view.glyphText = nil
                view.markerTintColor = .systemOrange
                view.clusteringIdentifier = "heardMe"
                view.displayPriority = .defaultHigh
                view.canShowCallout = true
                return view
            }

            // Grid labels cluster when they overlap, so hundreds of worked
            // squares do not each need a marker at world zoom.
            let id = "locator"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.glyphImage = nil
            view.glyphText = annotation.title ?? ""
            view.markerTintColor = .blue
            view.clusteringIdentifier = "locator"
            view.displayPriority = .defaultHigh
            return view
        }

        private static func tint(for member: MKAnnotation?) -> UIColor {
            switch member {
            case is HeardMeAnnotation: return .systemOrange
            case is PresenceAnnotation: return .systemCyan
            default: return .blue
            }
        }

        func mapView(
            _ mapView: MKMapView,
            didChange mode: MKUserTrackingMode,
            animated: Bool
        ) {
            Task { @MainActor in self.trackingModeBinding.wrappedValue = mode }
            guard mode == .follow || mode == .followWithHeading else { return }

            let locator =
                lastUserLocator
                ?? mapView.userLocation.location.map {
                    MaidenheadGrid.locator(
                        latitude: $0.coordinate.latitude,
                        longitude: $0.coordinate.longitude,
                        precision: 4
                    )
                }

            guard let locator else { return }
            zoomToGridSquare(locator: locator, on: mapView, animated: animated)
        }

        // MARK: - Helpers

        private func fitAll(_ mapView: MKMapView, overlays: [MKOverlay]) {
            let rect = overlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60),
                animated: true
            )
            hasEverFitRegion = true
        }

        private func zoomToGridSquare(locator: String, on mapView: MKMapView, animated: Bool) {
            guard let coordinates = MaidenheadGrid.gridPolygon(for: locator),
                  !coordinates.isEmpty else { return }

            let minLat = coordinates.map(\.latitude).min() ?? 0
            let maxLat = coordinates.map(\.latitude).max() ?? 0
            let minLon = coordinates.map(\.longitude).min() ?? 0
            let maxLon = coordinates.map(\.longitude).max() ?? 0

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )

            // Keep map focus around one Maidenhead square with a small visual margin.
            let paddingFactor = 1.15
            let span = MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * paddingFactor, 0.01),
                longitudeDelta: max((maxLon - minLon) * paddingFactor, 0.01)
            )

            mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: animated)
        }
    }
}

// MARK: - Helper Maidenhead Grid
// MARK: - Maidenhead Grid utilities

enum MaidenheadGrid {

    /// Converts latitude/longitude to a Maidenhead locator
    static func locator(latitude: Double,
                        longitude: Double,
                        precision: Int = 6) -> String {

        var lat = latitude + 90
        var lon = longitude + 180

        let fieldLon = Int(lon / 20)
        let fieldLat = Int(lat / 10)

        var locator = String(Character(UnicodeScalar(fieldLon + 65)!)) + String(Character(UnicodeScalar(fieldLat + 65)!))

        lon -= Double(fieldLon) * 20
        lat -= Double(fieldLat) * 10

        let squareLon = Int(lon / 2)
        let squareLat = Int(lat / 1)

        locator += "\(squareLon)\(squareLat)"

        guard precision >= 6 else { return locator }

        lon -= Double(squareLon) * 2
        lat -= Double(squareLat) * 1

        let subsquareLon = Int(lon / (5.0 / 60.0))
        let subsquareLat = Int(lat / (2.5 / 60.0))

        locator += String(Character(UnicodeScalar(subsquareLon + 97)!)) + String(Character(UnicodeScalar(subsquareLat + 97)!))

        return locator
    }

    /// Center of a 4- or 6-character Maidenhead locator; nil when malformed.
    static func center(for locator: String) -> CLLocationCoordinate2D? {
        guard let corners = gridPolygon(for: locator), corners.count == 4 else { return nil }
        let lat = corners.map(\.latitude).reduce(0, +) / 4
        let lon = corners.map(\.longitude).reduce(0, +) / 4
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Returns polygon corners for a Maidenhead grid
    static func gridPolygon(for locator: String) -> [CLLocationCoordinate2D]? {
        let chars = Array(locator.uppercased())
        guard chars.count >= 4 else { return nil }

        guard
            let lonBase = chars[0].asciiValue,
            let latBase = chars[1].asciiValue,
            let lonSquare = chars[2].wholeNumberValue,
            let latSquare = chars[3].wholeNumberValue
        else { return nil }

        var lon = Double(lonBase - 65) * 20 - 180 + Double(lonSquare) * 2
        var lat = Double(latBase - 65) * 10 - 90 + Double(latSquare)

        var lonDelta = 2.0
        var latDelta = 1.0

        if chars.count >= 6,
           let subLon = chars[4].lowercased().first?.asciiValue,
           let subLat = chars[5].lowercased().first?.asciiValue {
            lon += Double(subLon - 97) * (5.0 / 60.0)
            lat += Double(subLat - 97) * (2.5 / 60.0)
            lonDelta = 5.0 / 60.0
            latDelta = 2.5 / 60.0
        }

        return [
            CLLocationCoordinate2D(latitude: lat, longitude: lon),
            CLLocationCoordinate2D(latitude: lat, longitude: lon + lonDelta),
            CLLocationCoordinate2D(latitude: lat + latDelta, longitude: lon + lonDelta),
            CLLocationCoordinate2D(latitude: lat + latDelta, longitude: lon)
        ]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Safe area modifier

/// On iOS 18+ the tab bar is a translucent floating element, so the map should extend
/// fully edge-to-edge behind it (Apple Maps pattern). On iOS 17 and earlier the tab bar
/// is an opaque, fixed bar, so extending behind it causes UIKit layout conflicts; we
/// limit expansion to the top and side edges only.
struct MapSafeAreaModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.ignoresSafeArea()
        } else {
            content.ignoresSafeArea(.container, edges: [.top, .leading, .trailing])
        }
    }
}
