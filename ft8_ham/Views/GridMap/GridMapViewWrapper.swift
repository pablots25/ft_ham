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
    // Plain values (not bindings) so SwiftUI can compare them and skip this
    // body when nothing map-related changed.
    let locators: [String]
    let countries: [CountryPair]
    var routePoints: [CLLocationCoordinate2D] = []
    @ObservedObject var mapSettings: MapSettingsModel
    /// Stations that heard us (PSK Reporter). Omit to hide the feature.
    @ObservedObject var heardMe: HeardMeStore = .shared
    @ObservedObject var presence: PresenceManager = .shared
    var myCallsign: String = ""
    var myLocator: String = ""
    /// Called when the device location resolves to a grid square not yet shown.
    var onUserLocator: ((String) -> Void)? = nil
    @State private var userTrackingMode: MKUserTrackingMode = .none
    @State private var isControlsExpanded: Bool = false
    @State private var showMapLegend: Bool = false
    @State private var showHeardMeList: Bool = false

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
                locators: locators,
                countries: countries,
                routePoints: routePoints,
                heardMeStations: heardMe.stations,
                presenceStations: presence.visibleStations,
                showGrids: mapSettings.showGrids,
                showCountryCircles: mapSettings.showCountryCircles,
                showGeodesics: mapSettings.showGeodesics,
                showAnnotations: mapSettings.showAnnotations,
                showHeardMe: mapSettings.showHeardMe,
                showPresence: mapSettings.showPresence,
                userTrackingMode: $userTrackingMode,
                onUserLocator: onUserLocator
            )
            .modifier(MapSafeAreaModifier())

            mapControlBar
                .padding(10)
        }
        .onAppear {
            heardMe.refreshIfAllowed(callsign: myCallsign, myLocator: myLocator)
            presence.mapDidAppear()
        }
        .onDisappear {
            presence.mapDidDisappear()
        }
        .sheet(isPresented: $showHeardMeList) {
            HeardMeListView(store: heardMe, myCallsign: myCallsign, myLocator: myLocator)
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

    /// Tap: open the list. Long press: toggle the markers.
    private var heardMeButton: some View {
        Button {
            showHeardMeList = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: mapSettings.showHeardMe ? "ear.fill" : "ear")
                if mapSettings.showHeardMe, !heardMe.stations.isEmpty {
                    Text("\(heardMe.stations.count)")
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(mapSettings.showHeardMe ? .orange : .primary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                mapSettings.showHeardMe.toggle()
            } label: {
                Label(mapSettings.showHeardMe ? "Hide stations that heard me" : "Show stations that heard me",
                      systemImage: mapSettings.showHeardMe ? "eye.slash" : "eye")
            }
            ForEach(HeardMeWindow.allCases) { window in
                Button {
                    heardMe.window = window
                } label: {
                    if heardMe.window == window {
                        Label(window.title, systemImage: "checkmark")
                    } else {
                        Text(window.title)
                    }
                }
            }
        }
        .accessibilityLabel("Stations that heard you")
        .accessibilityIdentifier("button_heardMe")
    }

    /// Cyan marker toggle plus a count of operators currently on the air.
    private var presenceButton: some View {
        Button {
            mapSettings.showPresence.toggle()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "person.2.fill")
                if mapSettings.showPresence, !presence.visibleStations.isEmpty {
                    Text("\(presence.visibleStations.count)")
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(mapSettings.showPresence ? .cyan : .primary)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Operators Online")
        .accessibilityIdentifier("button_presence")
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
                        mapSettings.showGrids.toggle()
                    }
                } label: {
                    Image(systemName: mapSettings.showGrids ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .foregroundStyle(mapSettings.showGrids ? .blue : .primary)
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mapSettings.showCountryCircles.toggle()
                    }
                } label: {
                    Image(systemName: mapSettings.showCountryCircles ? "circle.dotted" : "circle")
                        .foregroundStyle(mapSettings.showCountryCircles ? .blue : .primary)
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mapSettings.showGeodesics.toggle()
                    }
                } label: {
                    Image(systemName: mapSettings.showGeodesics ? "point.bottomleft.forward.to.point.topright.scurvepath.fill" : "point.bottomleft.forward.to.point.topright.scurvepath")
                        .foregroundStyle(mapSettings.showGeodesics ? .blue : .primary)
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mapSettings.showAnnotations.toggle()
                    }
                } label: {
                    Image(systemName: mapSettings.showAnnotations ? "tag.fill" : "tag")
                        .foregroundStyle(mapSettings.showAnnotations ? .blue : .primary)
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

            heardMeButton

            if presence.isActive {
                Divider()

                presenceButton
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
