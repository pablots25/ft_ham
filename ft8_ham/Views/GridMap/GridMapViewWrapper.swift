//
//  GridMapViewWrapper.swift
//  ft_ham
//
//  A NavigationStack wrapper around GridMapView that exposes Binding-based
//  visibility toggles and handles the map toolbar in one place.
//

import SwiftUI

struct GridMapViewWrapper: View {

    @Binding var locators: [String]
    @Binding var countries: [CountryPair]
    @Binding var showGrids: Bool
    @Binding var showCountryCircles: Bool
    @Binding var showGeodesics: Bool
    @Binding var showAnnotations: Bool

    var body: some View {
        NavigationStack {
            GridMapView(
                locators: $locators,
                countries: countries,
                routePoints: [],
                showGrids: showGrids,
                showCountryCircles: showCountryCircles,
                showGeodesics: showGeodesics,
                showAnnotations: showAnnotations
            )
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showGrids.toggle()
                        } label: {
                            Label(
                                "Grids",
                                systemImage: showGrids ? "square.grid.3x3.fill" : "square.grid.3x3"
                            )
                        }
                        .tint(showGrids ? .blue : .primary)

                        Button {
                            showCountryCircles.toggle()
                        } label: {
                            Label(
                                "Countries",
                                systemImage: showCountryCircles ? "circle" : "circle.dotted"
                            )
                        }
                        .tint(showCountryCircles ? .blue : .primary)

                        Button {
                            showGeodesics.toggle()
                        } label: {
                            Label(
                                "Routes",
                                systemImage: showGeodesics
                                    ? "point.bottomleft.forward.to.point.topright.scurvepath.fill"
                                    : "point.bottomleft.forward.to.point.topright.scurvepath"
                            )
                        }
                        .tint(showGeodesics ? .blue : .primary)

                        Button {
                            showAnnotations.toggle()
                        } label: {
                            Label(
                                "Grid labels",
                                systemImage: showAnnotations ? "tag.fill" : "tag"
                            )
                        }
                        .tint(showAnnotations ? .blue : .primary)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(Text("Map display options"))
                }
            }
            .toolbarBackground(.ultraThickMaterial, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
