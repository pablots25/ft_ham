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
}

// MARK: - Map View with grids, countries, routes, and user location

struct GridMapView: UIViewRepresentable {

    /// Maidenhead locators to be displayed (including user grid)
    @Binding var locators: [String]

    /// Optional list of country pairs
    var countries: [CountryPair] = []

    /// Optional route points
    var routePoints: [CLLocationCoordinate2D] = []

    var showGrids: Bool = true
    var showCountryCircles: Bool = true
    var showGeodesics: Bool = true
    var showAnnotations: Bool = true
    @Binding var userTrackingMode: MKUserTrackingMode

    func makeCoordinator() -> Coordinator {
        Coordinator(locators: $locators, trackingMode: $userTrackingMode)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.attachMapView(mapView)

        mapView.showsCompass = false   // replaced by positioned MKCompassButton below
        mapView.showsScale = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isUserInteractionEnabled = true
        mapView.showsUserLocation = context.coordinator.canShowUserLocation
        mapView.pointOfInterestFilter = .excludingAll
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
        let visibility = MapVisibility(
            grids: showGrids,
            countryCircles: showCountryCircles,
            geodesics: showGeodesics,
            annotations: showAnnotations
        )
        context.coordinator.updateMap(uiView, locators: locators, countries: countries, visibility: visibility)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {

        // Bindings
        private let locatorsBinding: Binding<[String]>
        private let trackingModeBinding: Binding<MKUserTrackingMode>

        // Location
        private let locationManager = CLLocationManager()
        private var lastUserLocator: String?
        private weak var mapView: MKMapView?

        // Rendering caches
        private var polygonCache: [String: MKPolygon] = [:]
        private var annotationCache: [String: MKPointAnnotation] = [:]

        private var hasEverFitRegion = false
        private var lastHash: Int = 0

        init(locators: Binding<[String]>, trackingMode: Binding<MKUserTrackingMode>) {
            self.locatorsBinding = locators
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
            locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

            switch locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.startUpdatingLocation()
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                break
            @unknown default:
                break
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
                manager.startUpdatingLocation()
            case .denied, .restricted:
                mapView.showsUserLocation = false
                manager.stopUpdatingLocation()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }

        func locationManager(_ manager: CLLocationManager,
                             didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else { return }

            let locator = MaidenheadGrid.locator(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                precision: 4
            )

            // Avoid unnecessary updates
            guard locator != lastUserLocator else { return }
            lastUserLocator = locator

            Task { @MainActor in
                if !self.locatorsBinding.wrappedValue.contains(locator) {
                    self.locatorsBinding.wrappedValue.append(locator)
                }

                if let mapView = self.mapView,
                   mapView.userTrackingMode == .follow || mapView.userTrackingMode == .followWithHeading {
                    self.zoomToGridSquare(locator: locator, on: mapView, animated: true)
                }
            }
        }

        // MARK: - Map update

        @MainActor
        func updateMap(_ mapView: MKMapView, locators: [String], countries: [CountryPair], visibility: MapVisibility) {
            let currentHash = makeHash(locators: locators, countries: countries, visibility: visibility)
            guard currentHash != lastHash else { return }
            lastHash = currentHash

            var overlaysToAdd: [MKOverlay] = []
            var annotationsToAdd: [MKPointAnnotation] = []

            if visibility.grids {
                addGridOverlays(locators: locators, visibility: visibility, overlays: &overlaysToAdd, annotations: &annotationsToAdd)
            }

            if visibility.countryCircles || visibility.geodesics {
                addCountryOverlays(countries: countries, visibility: visibility, overlays: &overlaysToAdd)
            }

            updateMapOverlays(mapView, overlays: overlaysToAdd, annotations: annotationsToAdd, showAnnotations: visibility.annotations)

            if !hasEverFitRegion && !overlaysToAdd.isEmpty {
                fitAll(mapView, overlays: overlaysToAdd)
            }
        }

        // MARK: - Helper Methods

        private func makeHash(locators: [String], countries: [CountryPair], visibility: MapVisibility) -> Int {
            locators.hashValue ^ countries.count.hashValue ^ visibility.hashValue
        }

        private func addGridOverlays(locators: [String], visibility: MapVisibility,
                                     overlays: inout [MKOverlay], annotations: inout [MKPointAnnotation]) {
            for locator in locators {
                if let polygon = polygonCache[locator], let annotation = annotationCache[locator] {
                    overlays.append(polygon)
                    if visibility.annotations {
                        annotations.append(annotation)
                    }
                } else if let coords = MaidenheadGrid.gridPolygon(for: locator) {
                    let polygon = MKPolygon(coordinates: coords, count: coords.count)
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = polygonCenter(polygon)
                    annotation.title = locator.uppercased()

                    polygonCache[locator] = polygon
                    annotationCache[locator] = annotation

                    overlays.append(polygon)
                    if visibility.annotations {
                        annotations.append(annotation)
                    }
                }
            }
        }

        private func addCountryOverlays(countries: [CountryPair], visibility: MapVisibility, overlays: inout [MKOverlay]) {
            for pair in countries {
                guard let sender = pair.sender.coordinates.map({ CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }) else { continue }

                if visibility.countryCircles {
                    overlays.append(MKCircle(center: sender, radius: 150_000))
                }

                if let receiver = pair.receiver?.coordinates.map({ CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }) {
                    if visibility.countryCircles {
                        overlays.append(MKCircle(center: receiver, radius: 150_000))
                    }
                    if visibility.geodesics {
                        overlays.append(MKGeodesicPolyline(coordinates: [sender, receiver], count: 2))
                    }
                }
            }
        }

        private func updateMapOverlays(_ mapView: MKMapView,
                                       overlays: [MKOverlay],
                                       annotations: [MKPointAnnotation],
                                       showAnnotations: Bool) {
            mapView.removeOverlays(mapView.overlays)
            mapView.addOverlays(overlays)

            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            if showAnnotations {
                mapView.addAnnotations(annotations)
            }
        }

        // MARK: - Renderers

        func mapView(_ mapView: MKMapView,
                     rendererFor overlay: MKOverlay) -> MKOverlayRenderer {

            switch overlay {
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

            let id = "locator"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)

            view.glyphText = annotation.title ?? ""
            view.markerTintColor = .blue
            view.displayPriority = .required
            return view
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

        private func polygonCenter(_ polygon: MKPolygon) -> CLLocationCoordinate2D {
            let points = polygon.points()
            let count = polygon.pointCount
            var lat: Double = 0
            var lon: Double = 0
            for i in 0..<count {
                lat += points[i].coordinate.latitude
                lon += points[i].coordinate.longitude
            }
            return CLLocationCoordinate2D(latitude: lat / Double(count),
                                          longitude: lon / Double(count))
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
