//
//  GridMapView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 23/11/25.
//

import MapKit
import SwiftUI

// MARK: - Map View with multiple grids, optional countries, and routes

struct GridMapView: UIViewRepresentable {

    /// Maidenhead locators to be displayed
    @Binding var locators: [String]

    /// Optional list of country names to be displayed
    /// Countries are rendered independently from locators
    var countries: [CountryPair] = []
    
    /// Optional coordinates to draw a line/route
    var routePoints: [CLLocationCoordinate2D] = []

    func makeUIView(context: Context) -> MKMapView {
            let mapView = MKMapView()
            mapView.delegate = context.coordinator
            

            mapView.showsCompass = true
            mapView.showsScale = true
            mapView.isRotateEnabled = true
            mapView.showsUserLocation = true
            mapView.isPitchEnabled = true
            mapView.isScrollEnabled = true
            mapView.isZoomEnabled = true
            mapView.isUserInteractionEnabled = true
            
            mapView.pointOfInterestFilter = .excludingAll
            return mapView
        }

        func updateUIView(_ uiView: MKMapView, context: Context) {
            context.coordinator.updateMap(uiView, with: locators, countries: countries)
        }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    class Coordinator: NSObject, MKMapViewDelegate {
        private var polygonCache: [String: MKPolygon] = [:]
        private var annotationCache: [String: MKPointAnnotation] = [:]
        private var hasEverFitRegion = false
        private var lastHash: Int = 0

        @MainActor
        func updateMap(_ mapView: MKMapView, with locators: [String], countries: [CountryPair]) {
            let currentHash = locators.hashValue ^ countries.count.hashValue
            if currentHash == lastHash { return }
            lastHash = currentHash

            var newAnnotations: [MKPointAnnotation] = []
            var overlaysToAdd: [MKOverlay] = []

            // 1. Procesar Locators (Grids)
            for locator in locators {
                if let poly = polygonCache[locator], let anno = annotationCache[locator] {
                    overlaysToAdd.append(poly)
                    newAnnotations.append(anno)
                } else if let coords = MaidenheadGrid.gridPolygon(for: locator) {
                    let polygon = MKPolygon(coordinates: coords, count: coords.count)
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = polygonCenter(polygon)
                    annotation.title = locator.uppercased()
                    
                    polygonCache[locator] = polygon
                    annotationCache[locator] = annotation
                    
                    overlaysToAdd.append(polygon)
                    newAnnotations.append(annotation)
                }
            }

            // 2. Procesar Rutas Geodésicas (FT8 Contacts)
            for pair in countries {
                let sCoord = pair.sender.coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let rCoord = pair.receiver?.coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                
                if let s = sCoord {
                    overlaysToAdd.append(MKCircle(center: s, radius: 150_000))
                    if let r = rCoord {
                        overlaysToAdd.append(MKCircle(center: r, radius: 150_000))
                        // Ruta de círculo máximo (Short Path)
                        let geodesic = MKGeodesicPolyline(coordinates: [s, r], count: 2)
                        overlaysToAdd.append(geodesic)
                    }
                }
            }

            // 3. Actualización de UI
            mapView.removeOverlays(mapView.overlays)
            mapView.addOverlays(overlaysToAdd)
            mapView.removeAnnotations(mapView.annotations)
            mapView.addAnnotations(newAnnotations)

            if !hasEverFitRegion && !overlaysToAdd.isEmpty {
                fitAll(mapView, overlays: overlaysToAdd)
            }
        }

        // --- RENDERERS (UNIFICADOS) ---
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = .systemRed
                renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.2)
                renderer.lineWidth = 1.5
                return renderer
            }

            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = .systemGreen
                renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.15)
                renderer.lineWidth = 2
                return renderer
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                if polyline is MKGeodesicPolyline {
                    renderer.strokeColor = .systemBlue
                    renderer.lineWidth = 3.0
                    renderer.alpha = 0.8
                } else {
                    renderer.strokeColor = .gray
                    renderer.lineWidth = 1.0
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "locator"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                       ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.glyphText = annotation.title ?? ""
            view.markerTintColor = .blue
            view.displayPriority = .required
            return view
        }

        // --- HELPERS ---
        private func fitAll(_ mapView: MKMapView, overlays: [MKOverlay]) {
            let unionRect = overlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
            mapView.setVisibleMapRect(unionRect, edgePadding: UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60), animated: true)
            hasEverFitRegion = true
        }

        private func polygonCenter(_ polygon: MKPolygon) -> CLLocationCoordinate2D {
            let points = polygon.points()
            let count = polygon.pointCount
            var sumLat: Double = 0
            var sumLon: Double = 0
            for i in 0..<count {
                sumLat += points[i].coordinate.latitude
                sumLon += points[i].coordinate.longitude
            }
            return CLLocationCoordinate2D(latitude: sumLat / Double(count), longitude: sumLon / Double(count))
        }
    }
}


// MARK: - Helper Maidenhead Grid

enum MaidenheadGrid {
    /// Generates a four-point polygon for a Maidenhead locator (e.g., "IN73" or "IN73ab")
    static func gridPolygon(for locator: String) -> [CLLocationCoordinate2D]? {
        let chars = Array(locator.uppercased())
        guard chars.count >= 4 else { return nil }

        guard let lonBase = chars[safe: 0]?.asciiValue, lonBase >= 65, lonBase <= 90, // A-R
              let latBase = chars[safe: 1]?.asciiValue, latBase >= 65, latBase <= 90, // A-R
              let lonSquare = chars[safe: 2]?.wholeNumberValue,
              let latSquare = chars[safe: 3]?.wholeNumberValue else { return nil }

        var lon = Double(lonBase - 65) * 20.0 - 180.0 + Double(lonSquare) * 2.0
        var lat = Double(latBase - 65) * 10.0 - 90.0 + Double(latSquare) * 1.0
        var lonDelta = 2.0
        var latDelta = 1.0

        // Handle sub-squares (e.g., "aa", "ab")
        if chars.count >= 6 {
            let subLonChar = chars[4].lowercased()
            let subLatChar = chars[5].lowercased()
            if let subLonAscii = subLonChar.first?.asciiValue, subLonAscii >= 97, subLonAscii <= 120,
               let subLatAscii = subLatChar.first?.asciiValue, subLatAscii >= 97, subLatAscii <= 120 {
                lon += Double(subLonAscii - 97) * (5.0 / 60.0)
                lat += Double(subLatAscii - 97) * (2.5 / 60.0)
                lonDelta = 5.0 / 60.0
                latDelta = 2.5 / 60.0
            }
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
