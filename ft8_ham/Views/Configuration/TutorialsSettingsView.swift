//
//  TutorialsSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import SwiftUI

/// Lets the operator bring back the onboarding tour and the one-time help tips.
struct TutorialsSettingsContent: View {
    @State private var isPresentingFeatureTour = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                isPresentingFeatureTour = true
            } label: {
                Label("onb_feature_tour", systemImage: "rectangle.stack")
            }

            Button {
                AppStorageResetter.resetTutorials()
            } label: {
                Label("Reset help messages", systemImage: "arrow.counterclockwise")
            }

            Button {
                AppStorageResetter.resetOnboarding()
            } label: {
                Label("Show initial tutorial", systemImage: "play.circle")
            }

            Text("Re-display help messages or the initial onboarding tutorial.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isPresentingFeatureTour) {
            FeatureTourView()
        }
    }
}

struct TutorialsSettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Tutorials", alignment: .leading, spacing: 20) {
            TutorialsSettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        TutorialsSettingsView()
    }
}
