//
//  GridMapViewWrapper.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import MapKit
import SwiftUI
import CoreLocation

struct GridMapViewWrapper: View {
    @Binding var locators: [String]
    @Binding var countries: [CountryPair]
    var routePoints: [CLLocationCoordinate2D] = []
    @Binding var showGrids: Bool
    @Binding var showCountryCircles: Bool
    @Binding var showGeodesics: Bool
    @Binding var showAnnotations: Bool
    @State private var userTrackingMode: MKUserTrackingMode = .none
    @State private var isControlsExpanded: Bool = false
    @State private var showMapLegend: Bool = false

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            mapContent
                .toolbarVisibility(.visible, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        } else {
            mapContent
        }
    }

    private var mapContent: some View {
        ZStack(alignment: .topTrailing) {
            GridMapView(
                locators: $locators,
                countries: countries,
                routePoints: routePoints,
                showGrids: showGrids,
                showCountryCircles: showCountryCircles,
                showGeodesics: showGeodesics,
                showAnnotations: showAnnotations,
                userTrackingMode: $userTrackingMode
            )
            .modifier(MapSafeAreaModifier())

            mapControlBar
                .padding(10)
        }
    }

    // MARK: - Floating Map Controls

    private var trackingModeIcon: String {
        switch userTrackingMode {
        case .follow: return "location.fill"
        case .followWithHeading: return "location.north.fill"
        default: return "location"
        }
    }

    private var mapControlBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.3)) {
                    isControlsExpanded.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(isControlsExpanded ? .green : .primary)
            }
            .frame(height: 30)

            if isControlsExpanded {
                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showGrids.toggle()
                    }
                } label: {
                    Image(systemName: showGrids ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .foregroundStyle(showGrids ? .blue : .primary)
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCountryCircles.toggle()
                    }
                } label: {
                    Image(systemName: showCountryCircles ? "circle.dotted" : "circle")
                        .foregroundStyle(showCountryCircles ? .blue : .primary)
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showGeodesics.toggle()
                    }
                } label: {
                    Image(systemName: showGeodesics ? "point.bottomleft.forward.to.point.topright.scurvepath.fill" : "point.bottomleft.forward.to.point.topright.scurvepath")
                        .foregroundStyle(showGeodesics ? .blue : .primary)
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAnnotations.toggle()
                    }
                } label: {
                    Image(systemName: showAnnotations ? "tag.fill" : "tag")
                        .foregroundStyle(showAnnotations ? .blue : .primary)
                }
            }

            Divider()

            Button {
                switch userTrackingMode {
                case .none:
                    userTrackingMode = .follow
                case .follow:
                    userTrackingMode = .followWithHeading
                default:
                    userTrackingMode = .none
                }
            } label: {
                Image(systemName: trackingModeIcon)
                    .foregroundStyle(userTrackingMode == .none ? Color.secondary : Color.blue)
            }

            Divider()

            Button {
                showMapLegend.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showMapLegend) {
                MapLegendView()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .frame(height: 40)
        .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.3), value: isControlsExpanded)
    }
}
