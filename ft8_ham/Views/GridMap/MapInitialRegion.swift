//
//  MapInitialRegion.swift
//  ft_ham
//

import MapKit

/// Where the map opens: centered on the operator's own station, zoomed out
/// far enough to show everything already drawn around it.
enum MapInitialRegion {
    /// Span when there is nothing else on the map yet: a wide area around
    /// the station, about a continent.
    static let defaultSpan = MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40)
    /// Never zoom in closer than this, so a single nearby contact does not
    /// open the map on a few streets.
    static let minimumSpan = MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 10)
    /// Margin around the farthest drawn point.
    static let paddingFactor = 1.1

    /// - Parameters:
    ///   - home: The station's position, the center of the region.
    ///   - content: The bounding rect of the drawn layers, if any.
    static func region(home: CLLocationCoordinate2D, content: MKMapRect?) -> MKCoordinateRegion {
        guard let content, !content.isNull, !content.isEmpty else {
            return MKCoordinateRegion(center: home, span: defaultSpan)
        }
        let bounds = MKCoordinateRegion(content)
        let north = bounds.center.latitude + bounds.span.latitudeDelta / 2
        let south = bounds.center.latitude - bounds.span.latitudeDelta / 2
        let east = bounds.center.longitude + bounds.span.longitudeDelta / 2
        let west = bounds.center.longitude - bounds.span.longitudeDelta / 2

        // Symmetric around home, so home stays in the middle.
        let latReach = max(abs(north - home.latitude), abs(home.latitude - south))
        let lonReach = max(abs(east - home.longitude), abs(home.longitude - west))
        let span = MKCoordinateSpan(
            latitudeDelta: (latReach * 2 * paddingFactor).clamped(to: minimumSpan.latitudeDelta...170),
            longitudeDelta: (lonReach * 2 * paddingFactor).clamped(to: minimumSpan.longitudeDelta...360)
        )
        return MKCoordinateRegion(center: home, span: span)
    }
}
