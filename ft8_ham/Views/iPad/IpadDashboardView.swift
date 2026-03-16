//
//  IpadDashboardView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 2026-02-26.
//

import SwiftUI

struct IpadDashboardView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @EnvironmentObject private var mapSettings: MapSettingsModel
    
    @State private var isSettingFrequency: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            Group {
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
            .padding(LayoutConstants.standardPadding)
        }
    }

    private var portraitLayout: some View {
        VStack(spacing: LayoutConstants.standardSpacing) {
            // Consolidated transmission control panel with messages
            SeparatedTransmissionDashboardView()
            
            HStack(spacing: LayoutConstants.standardSpacing) {
                dashboardSection(title: String(localized: "Waterfall")) {
                    WaterfallDashboardView()
                        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius, style: .continuous))
                }
                
                dashboardSection(title: String(localized: "Map")) {
                    mapContent
                }
            }
        }
    }

    private var landscapeLayout: some View {
        HStack(spacing: LayoutConstants.standardSpacing) {
            SeparatedTransmissionDashboardView()
                .frame(maxWidth: .infinity)

            VStack(spacing: LayoutConstants.standardSpacing) {
                dashboardSection(title: String(localized: "Waterfall")) {
                    WaterfallDashboardView()
                }

                dashboardSection(title: String(localized: "Map")) {
                    mapContent
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var mapContent: some View {
        GridMapViewWrapper(
            locators: $viewModel.workedLocators,
            countries: $viewModel.workedCountryPairs,
            showGrids: $mapSettings.showGrids,
            showCountryCircles: $mapSettings.showCountryCircles,
            showGeodesics: $mapSettings.showGeodesics,
            showAnnotations: $mapSettings.showAnnotations
        )
        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func dashboardSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LayoutConstants.compactSpacing) {
            Text(title)
                .font(.headline)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(LayoutConstants.standardPadding)
        .clipShape(RoundedRectangle(cornerRadius: LayoutConstants.standardCornerRadius, style: .continuous))
    }
}

#Preview("iPad Dashboard") {
    IpadDashboardView()
        .environmentObject(
            FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            )
        )
        .environmentObject(MapSettingsModel.shared)
}
