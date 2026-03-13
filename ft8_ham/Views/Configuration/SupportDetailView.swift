//
//  SupportDetailView.swift
//  ft_ham
//
//  Detail screen for Help, Donations, and Contact.
//  Extracted from ConfigurationView for Apple-standard NavigationLink pattern.
//

import SwiftUI

struct SupportDetailView: View {
    @State private var showHelp = false
    @State private var showResetHelpAlert = false
    @State private var showResetOnboardingAlert = false

    var body: some View {
        Form {
            Section {
                Button {
                    showHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }

                Button("Reset help messages") {
                    showResetHelpAlert = true
                }

                Button("Show initial tutorial") {
                    showResetOnboardingAlert = true
                }
            } header: {
                Text("Help")
            }

            Section {
                SupportView()
            } header: {
                Text("Donations")
            }

            Section {
                ContactView()
            } header: {
                Text("Contact")
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHelp) {
            SafariView(
                url: URL(string: "https://ftham.turrion.dev/#getting-started")!
            )
            .ignoresSafeArea()
        }
        .alert("Reset Help Messages?", isPresented: $showResetHelpAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                AppStorageResetter.resetTutorials()
            }
        } message: {
            Text("This will show all help tips again.")
        }
        .alert("Show Initial Tutorial?", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                AppStorageResetter.resetOnboarding()
            }
        } message: {
            Text("This will replay the onboarding screens on next launch.")
        }
    }
}

// MARK: - Preview

#Preview("SupportDetailView") {
    NavigationStack {
        SupportDetailView()
    }
}
