//
//  MapOverlayModel.swift
//  ft_ham
//
//  Created by Pablo Turrion on 5/10/26.
//

import MapKit
import CoreLocation

/// Pure description of what the map draws, built from the worked locators and
/// country pairs.
///
/// MapKit's cost grows with the number of overlays, so each layer (grid
/// squares, country circles, geodesics) is drawn as a single multi-shape
/// overlay with one renderer. Each layer is described by plain `Hashable`
/// keys so the map can tell which layers changed and rebuild only those.
enum MapOverlayModel {

    enum Constants {
        /// Radius of the circle drawn around each country's reference point.
        static let countryCircleRadiusMeters: CLLocationDistance = 150_000
        /// Vertices used to approximate each country circle.
        static let circleSegments = 64
        /// Rounding applied to coordinates before deduplicating (about 11 m).
        static let coordinatePrecision = 10_000.0
    }

    /// A coordinate rounded so near-identical points compare equal.
    struct PointKey: Hashable {
        let latE4: Int
        let lonE4: Int

        init(_ coordinate: CLLocationCoordinate2D) {
            latE4 = Int((coordinate.latitude * Constants.coordinatePrecision).rounded())
            lonE4 = Int((coordinate.longitude * Constants.coordinatePrecision).rounded())
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: Double(latE4) / Constants.coordinatePrecision,
                                   longitude: Double(lonE4) / Constants.coordinatePrecision)
        }
    }

    /// A path between two points, independent of direction (A→B equals B→A).
    struct SegmentKey: Hashable {
        let a: PointKey
        let b: PointKey

        init(_ p: PointKey, _ q: PointKey) {
            if (p.latE4, p.lonE4) <= (q.latE4, q.lonE4) {
                a = p; b = q
            } else {
                a = q; b = p
            }
        }
    }

    // MARK: - Layer keys

    /// Valid locators, uppercased and deduplicated, in first-seen order.
    static func gridKeys(for locators: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for locator in locators {
            let key = locator.uppercased()
            guard !seen.contains(key), MaidenheadGrid.gridPolygon(for: key) != nil else { continue }
            seen.insert(key)
            result.append(key)
        }
        return result
    }

    /// One circle per distinct sender or receiver location.
    static func circleKeys(for countries: [CountryPair]) -> [PointKey] {
        var seen = Set<PointKey>()
        var result: [PointKey] = []
        for pair in countries {
            guard let sender = coordinate(of: pair.sender) else { continue }
            for point in [sender, pair.receiver.flatMap(coordinate(of:))].compactMap({ $0 }) {
                let key = PointKey(point)
                if seen.insert(key).inserted { result.append(key) }
            }
        }
        return result
    }

    /// One geodesic per distinct sender/receiver pair, ignoring direction and
    /// pairs whose ends fall on the same point.
    static func segmentKeys(for countries: [CountryPair]) -> [SegmentKey] {
        var seen = Set<SegmentKey>()
        var result: [SegmentKey] = []
        for pair in countries {
            guard let sender = coordinate(of: pair.sender),
                  let receiver = pair.receiver.flatMap(coordinate(of:)) else { continue }
            let p = PointKey(sender), q = PointKey(receiver)
            guard p != q else { continue }
            let key = SegmentKey(p, q)
            if seen.insert(key).inserted { result.append(key) }
        }
        return result
    }

    // MARK: - Overlay builders

    static func gridOverlay(for keys: [String]) -> MKMultiPolygon? {
        let polygons = keys.compactMap { locator -> MKPolygon? in
            guard let coords = MaidenheadGrid.gridPolygon(for: locator) else { return nil }
            return MKPolygon(coordinates: coords, count: coords.count)
        }
        return polygons.isEmpty ? nil : MKMultiPolygon(polygons)
    }

    static func circleOverlay(for keys: [PointKey]) -> MKMultiPolygon? {
        let polygons = keys.map { circlePolygon(center: $0.coordinate) }
        return polygons.isEmpty ? nil : MKMultiPolygon(polygons)
    }

    static func geodesicOverlay(for keys: [SegmentKey]) -> MKMultiPolyline? {
        let lines: [MKPolyline] = keys.map {
            MKGeodesicPolyline(coordinates: [$0.a.coordinate, $0.b.coordinate], count: 2)
        }
        return lines.isEmpty ? nil : MKMultiPolyline(lines)
    }

    /// The ring `MKCircle` would draw: round in map-point (Mercator) space,
    /// scaled for the centre's latitude.
    static func circlePolygon(center: CLLocationCoordinate2D,
                              radius: CLLocationDistance = Constants.countryCircleRadiusMeters,
                              segments: Int = Constants.circleSegments) -> MKPolygon {
        let origin = MKMapPoint(center)
        let r = radius * MKMapPointsPerMeterAtLatitude(center.latitude)
        var points = (0..<segments).map { i -> MKMapPoint in
            let angle = Double(i) / Double(segments) * 2 * .pi
            return MKMapPoint(x: origin.x + r * cos(angle), y: origin.y + r * sin(angle))
        }
        return MKPolygon(points: &points, count: points.count)
    }

    private static func coordinate(of info: CountryInfo) -> CLLocationCoordinate2D? {
        info.coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
}

// MARK: - Annotation diffing

/// Identity of a map marker. Station keys carry the whole station so a
/// changed SNR or "last seen" replaces the marker and refreshes its callout.
enum MapAnnotationKey: Hashable {
    case grid(String)
    case heardMe(HeardMeStation)
    case presence(PresenceStation)
}

struct MapAnnotationDiff: Equatable {
    let added: [MapAnnotationKey]
    let removed: Set<MapAnnotationKey>

    var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// Keys in `desired` that are not on the map yet, and keys on the map
    /// that are no longer wanted. `desired` order is kept for additions.
    init(current: Set<MapAnnotationKey>, desired: [MapAnnotationKey]) {
        let desiredSet = Set(desired)
        var seen = Set<MapAnnotationKey>()
        added = desired.filter { !current.contains($0) && seen.insert($0).inserted }
        removed = current.subtracting(desiredSet)
    }
}
