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
    @State private var isParsing = false
    @State private var isCommitting = false
    @State private var parseError: String?

    // Preview state — populated after parsing, before committing
    @State private var previewEntries: [LogEntry] = []
    @State private var previewSkipped: Int = 0
    @State private var fileName: String = ""

    private var isPreviewing: Bool { !previewEntries.isEmpty || previewSkipped > 0 }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Instructions
                if !isPreviewing {
                    Section {
                        Text("Select an ADIF file (.adi / .adif). You'll see a preview before anything is imported. Duplicate entries are skipped based on callsign, band, and time (±2 min).")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                // MARK: File picker button
                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label(
                            isPreviewing ? "Choose a Different File…" : "Choose ADIF File…",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .disabled(isParsing || isCommitting)
                }

                // MARK: Parsing progress
                if isParsing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading file…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Parse error
                if let error = parseError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                // MARK: Preview
                if isPreviewing {
                    Section {
                        if !fileName.isEmpty {
                            LabeledContent("File", value: fileName)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("New QSOs to import", value: "\(previewEntries.count)")
                        LabeledContent("Duplicates (skipped)", value: "\(previewSkipped)")
                    } header: {
                        Text("Preview")
                    } footer: {
                        if previewEntries.isEmpty {
                            Text("Nothing new to import — all records are duplicates.")
                        }
                    }

                    // Sample of first 5 callsigns
                    if !previewEntries.isEmpty {
                        Section {
                            ForEach(previewEntries.prefix(5), id: \.id) { entry in
                                HStack {
                                    if let flag = entry.flag { Text(flag) }
                                    Text(entry.callsign).fontWeight(.medium)
                                    Spacer()
                                    Text(entry.band).foregroundStyle(.secondary).font(.caption)
                                    Text(entry.mode).foregroundStyle(.secondary).font(.caption)
                                }
                            }
                            if previewEntries.count > 5 {
                                Text("… and \(previewEntries.count - 5) more")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        } header: {
                            Text("Sample")
                        }
                    }

                    // MARK: Import button
                    if !previewEntries.isEmpty {
                        Section {
                            Button {
                                commitImport()
                            } label: {
                                if isCommitting {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                        Text("Importing…")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                } else {
                                    Text("Import \(previewEntries.count) QSO\(previewEntries.count == 1 ? "" : "s")")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .fontWeight(.semibold)
                                }
                            }
                            .disabled(isCommitting)
                        }
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
                    runPreview(url: url)
                case .failure(let error):
                    parseError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Parse (preview only, no write)

    private func runPreview(url: URL) {
        isParsing = true
        parseError = nil
        previewEntries = []
        previewSkipped = 0
        fileName = url.lastPathComponent

        let existingEntries = viewModel.qsoList
        let manager = viewModel.logbookManager

        Task {
            let (newEntries, skipped, error) = await Task.detached(priority: .userInitiated) {
                manager.previewADIF(url: url, existingEntries: existingEntries)
            }.value

            if let error {
                parseError = error
            } else {
                previewEntries = newEntries
                previewSkipped = skipped
            }
            isParsing = false
        }
    }

    // MARK: - Commit (write + dismiss)

    private func commitImport() {
        isCommitting = true
        let entriesToWrite = previewEntries
        let existingEntries = viewModel.qsoList
        let manager = viewModel.logbookManager

        Task {
            await Task.detached(priority: .userInitiated) {
                manager.commitImport(newEntries: entriesToWrite, existingEntries: existingEntries)
            }.value

            do {
                viewModel.qsoList = try manager.loadEntries()
            } catch {
                // Non-fatal — entries are on disk; the reload will happen next launch
            }

            lastImportResult = ImportResult(imported: entriesToWrite.count, skipped: previewSkipped)
            isCommitting = false
            dismiss()
        }
    }
}
