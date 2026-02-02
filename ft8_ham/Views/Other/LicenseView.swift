//
//  LicenseView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/11/25.
//

import SwiftUI

struct LicenseView: View {
    @State private var showingLicenses = false

    var body: some View {
        VStack(spacing: 10) {
            Button("Legal & Licenses") {
                showingLicenses = true
            }
            .sheet(isPresented: $showingLicenses) {
                LicenseDialogView()
            }

            Button("Privacy Policy") {
                if let url = URL(string: "https://ftham.turrion.dev/privacy") {
                    UIApplication.shared.open(url)
                }
            }

            Button("Terms of Use") {
                if let url = URL(string: "https://ftham.turrion.dev/terms") {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding()
    }
}

struct LicenseDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseSections: [LicenseSection] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(licenseSections, id: \.id) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.headline)
                        }
                        Text(section.body)
                            .font(.system(.body))
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Licenses & EULA")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { loadLicenses() }
        }
    }

    private func loadLicenses() {
        guard let path = Bundle.main.path(forResource: "Licenses", ofType: "txt") else {
            licenseSections = [LicenseSection(title: nil, body: "Licenses.txt not found in bundle.")]
            return
        }
        do {
            let fullText = try String(contentsOfFile: path, encoding: .utf8)
            licenseSections = parseLicenseSections(from: fullText)
        } catch {
            licenseSections = [LicenseSection(
                title: nil,
                body: "Failed to read Licenses.txt: \(error.localizedDescription)"
            )]
        }
    }

    private func parseLicenseSections(from text: String) -> [LicenseSection] {
        // Split the text by "---" markers
        let parts = text.components(separatedBy: "---").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.map { part in
            let lines = part.components(separatedBy: "\n")
            if let firstLine = lines.first {
                let body = lines.dropFirst().joined(separator: "\n")
                return LicenseSection(title: firstLine, body: body)
            } else {
                return LicenseSection(title: nil, body: part)
            }
        }
    }
}

struct LicenseSection: Identifiable {
    let id = UUID()
    let title: String?
    let body: String
}
