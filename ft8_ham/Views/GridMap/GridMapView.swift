//
//  GridMapView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 23/11/25.
//

import MapKit
import SwiftUI
import CoreLocation

// MARK: - Map View with grids, countries, routes, and user location

struct GridMapView: UIViewRepresentable {

    /// Maidenhead locators to be displayed (including user grid)
    @Binding var locators: [String]

    /// Optional list of country pairs
    var countries: [CountryPair] = []

    /// Optional route points
    var routePoints: [CLLocationCoordinate2D] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(locators: $locators)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isUserInteractionEnabled = true
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll

        context.coordinator.configureLocationManager()

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.updateMap(
            uiView,
            locators: locators,
            countries: countries
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {

        // Bindings
        private let locatorsBinding: Binding<[String]>

        // Location
        private let locationManager = CLLocationManager()
        private var lastUserLocator: String?

        // Rendering caches
        private var polygonCache: [String: MKPolygon] = [:]
        private var annotationCache: [String: MKPointAnnotation] = [:]

        private var hasEverFitRegion = false
        private var lastHash: Int = 0

        init(locators: Binding<[String]>) {
            self.locatorsBinding = locators
            super.init()
            locationManager.delegate = self
        }

        // MARK: - Location handling

        func configureLocationManager() {
            locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
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

            DispatchQueue.main.async {
                if !self.locatorsBinding.wrappedValue.contains(locator) {
                    self.locatorsBinding.wrappedValue.append(locator)
                }
            }
        }

        // MARK: - Map update

        @MainActor
        func updateMap(_ mapView: MKMapView,
                       locators: [String],
                       countries: [CountryPair]) {

            let currentHash = locators.hashValue ^ countries.count.hashValue
            guard currentHash != lastHash else { return }
            lastHash = currentHash

            var overlaysToAdd: [MKOverlay] = []
            var annotationsToAdd: [MKPointAnnotation] = []

            // Grids
            for locator in locators {
                if let polygon = polygonCache[locator],
                   let annotation = annotationCache[locator] {
                    overlaysToAdd.append(polygon)
                    annotationsToAdd.append(annotation)
                } else if let coords = MaidenheadGrid.gridPolygon(for: locator) {
                    let polygon = MKPolygon(coordinates: coords, count: coords.count)
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = polygonCenter(polygon)
                    annotation.title = locator.uppercased()

                    polygonCache[locator] = polygon
                    annotationCache[locator] = annotation

                    overlaysToAdd.append(polygon)
                    annotationsToAdd.append(annotation)
                }
            }

            // Country circles and geodesics
            for pair in countries {
                let sender = pair.sender.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
                let receiver = pair.receiver?.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }

                if let s = sender {
                    overlaysToAdd.append(MKCircle(center: s, radius: 150_000))
                    if let r = receiver {
                        overlaysToAdd.append(MKCircle(center: r, radius: 150_000))
                        overlaysToAdd.append(MKGeodesicPolyline(coordinates: [s, r], count: 2))
                    }
                }
            }

            mapView.removeOverlays(mapView.overlays)
            mapView.addOverlays(overlaysToAdd)

            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            mapView.addAnnotations(annotationsToAdd)

            if !hasEverFitRegion && !overlaysToAdd.isEmpty {
                fitAll(mapView, overlays: overlaysToAdd)
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

// MARK: - Wrapper

struct GridMapViewWrapper: View {
    @Binding var locators: [String]
    @Binding var countries: [CountryPair]
    var routePoints: [CLLocationCoordinate2D] = []

    var body: some View {
        GeometryReader { geo in
            GridMapView(
                locators: $locators,
                countries: countries,
                routePoints: routePoints
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

