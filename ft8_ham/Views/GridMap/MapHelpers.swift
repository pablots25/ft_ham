//
//  MapHelpers.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 8/1/26.
//

import MapKit

func generateQuadraticBezierPointsMK(start: MKMapPoint,
                                     control: MKMapPoint,
                                     end: MKMapPoint,
                                     segments: Int) -> [CLLocationCoordinate2D] {
    guard segments > 1 else { return [start.coordinate, end.coordinate] }
    var points: [CLLocationCoordinate2D] = []
    for i in 0...segments {
        let t = Double(i) / Double(segments)
        let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * control.x + pow(t, 2) * end.x
        let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * control.y + pow(t, 2) * end.y
        points.append(MKMapPoint(x: x, y: y).coordinate)
    }
    return points
}

func distanceBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
    let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
    return locA.distance(from: locB) // distance in meters
}
