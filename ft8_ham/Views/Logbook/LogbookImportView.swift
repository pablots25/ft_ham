//
//  LogbookImportView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 4/4/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct LogbookImportView: View {
    @EnvironmentObject var viewModel: FT8ViewModel
    @Environment(\.dismiss) private var dismiss
    /// Set by the caller to receive the result when the sheet is dismissed.
    @Binding var lastImportResult: ImportResult?
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Import QSOs from an ADIF file (.adi / .adif). Duplicate entries are automatically skipped based on callsign, band, and time (±2 min).")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Choose ADIF File…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImporting)
                }

                if isImporting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Importing…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let result = importResult {
                    Section {
                        LabeledContent("Imported", value: "\(result.imported)")
                        LabeledContent("Skipped (duplicates)", value: "\(result.skipped)")
                    } header: {
                        Text("Result")
                    }
                }

                if let error = importError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import ADIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton()
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "adi") ?? .data,
                    UTType(filenameExtension: "adif") ?? .data,
                    .data
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    runImport(url: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func runImport(url: URL) {
        isImporting = true
        importResult = nil
        importError = nil

        let existingEntries = viewModel.qsoList
        let manager = viewModel.logbookManager

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                manager.importFromADIF(url: url, existingEntries: existingEntries)
            }.value

            if let error = result.error {
                importError = error
            } else {
                do {
                    viewModel.qsoList = try manager.loadEntries()
                } catch {
                    importError = "Could not reload logbook after import: \(error.localizedDescription)"
                }
            }
            importResult = result
            if result.error == nil {
                lastImportResult = result
            }
            isImporting = false
        }
    }
}
