//
//  MapHelpers.swift
//  ft_ham
//
//  Created by Pablo Turrion on 8/1/26.
//

import MapKit
import CoreLocation

// MARK: - Geometry helpers

func generateQuadraticBezierPointsMK(start: MKMapPoint,
                                     control: MKMapPoint,
                                     end: MKMapPoint,
                                     segments: Int) -> [CLLocationCoordinate2D] {
    guard segments > 1 else {
        return [start.coordinate, end.coordinate]
    }

    return (0...segments).map { i in
        let t = Double(i) / Double(segments)
        let x = pow(1 - t, 2) * start.x
              + 2 * (1 - t) * t * control.x
              + pow(t, 2) * end.x
        let y = pow(1 - t, 2) * start.y
              + 2 * (1 - t) * t * control.y
              + pow(t, 2) * end.y
        return MKMapPoint(x: x, y: y).coordinate
    }
}

func distanceBetween(_ a: CLLocationCoordinate2D,
                     _ b: CLLocationCoordinate2D) -> Double {
    CLLocation(latitude: a.latitude, longitude: a.longitude)
        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
}
