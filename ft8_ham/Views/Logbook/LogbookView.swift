//
//  LogbookView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 1/1/26.
//

import SwiftUI

// MARK: - LogbookView

struct LogbookView: View {
    @EnvironmentObject var viewModel: FT8ViewModel

    @AppStorage("logbookTimeDisplayLocal") private var displayLocalTime: Bool = false
    @State private var showingImportSheet = false
    @State private var searchText = ""
    @State private var filteredQSOs: [LogEntry] = []
    @State private var editingEntry: LogEntry?
    @State private var lastImportResult: ImportResult?
    @State private var showImportResultAlert = false
    @State private var expandedIDs: Set<UUID> = []

    // MARK: - Filtering

    private func applyFilter() {
        let source = viewModel.sortedQSOList
        guard !searchText.isEmpty else {
            filteredQSOs = source
            return
        }
        let q = searchText.lowercased()
        filteredQSOs = source.filter { matches($0, query: q) }
    }

    private func matches(_ entry: LogEntry, query q: String) -> Bool {
        if entry.callsign.lowercased().contains(q) { return true }
        if entry.grid.lowercased().contains(q) { return true }
        if entry.country?.lowercased().contains(q) == true { return true }
        if entry.mode.lowercased().contains(q) { return true }
        if entry.band.lowercased().contains(q) { return true }
        return false
    }

    var body: some View {
        List {
            ForEach(filteredQSOs) { entry in
                LogbookRowCell(
                    entry: entry,
                    isExpanded: expandedIDs.contains(entry.id),
                    displayLocalTime: displayLocalTime,
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedIDs.contains(entry.id) {
                                expandedIDs.remove(entry.id)
                            } else {
                                expandedIDs.insert(entry.id)
                            }
                        }
                    },
                    onEdit: { editingEntry = entry }
                )
            }
            .onDelete(perform: deleteQSOs)
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Callsign, grid, country, mode, band…")
        .onChange(of: searchText) { _ in applyFilter() }
        .onChange(of: viewModel.qsoList.count) { _ in applyFilter() }
        .onChange(of: viewModel.qsoList.first?.id) { _ in applyFilter() }
        .onAppear { applyFilter() }
        .overlay {
            if viewModel.qsoList.isEmpty {
                VStack {
                    Spacer()
                    Text("Empty logbook")
                        .foregroundStyle(.gray)
                        .font(.body)
                    Spacer()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    displayLocalTime.toggle()
                } label: {
                    Label(
                        displayLocalTime ? "Local" : "UTC",
                        systemImage: "clock"
                    )
                }
                .accessibilityLabel(
                    displayLocalTime
                    ? "Display time in local timezone"
                    : "Display time in UTC"
                )
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Import ADIF", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("Import QSOs from ADIF file")
            }
        }
        .sheet(
            isPresented: $showingImportSheet,
            onDismiss: { if lastImportResult != nil { showImportResultAlert = true } },
            content: {
                LogbookImportView(lastImportResult: $lastImportResult)
                    .environmentObject(viewModel)
            }
        )
        .sheet(item: $editingEntry) { entry in
            QSOEditView(entry: entry) { updated in
                if let idx = viewModel.qsoList.firstIndex(where: { $0.id == updated.id }) {
                    viewModel.qsoList[idx] = updated
                }
            }
        }
        .alert("Import Complete", isPresented: $showImportResultAlert) {
            Button("OK") { lastImportResult = nil }
        } message: {
            if let result = lastImportResult {
                Text("\(result.imported) QSO(s) imported, \(result.skipped) skipped (duplicates).")
            }
        }
        .alert("Logbook Error", isPresented: Binding(
            get: { viewModel.logbookLoadError != nil },
            set: { if !$0 { viewModel.logbookLoadError = nil } }
        )) {
            if viewModel.logbookManager.hasBackup {
                Button("Restore Backup") { viewModel.restoreLogbookFromBackup() }
            }
            Button("Clear & Start Over", role: .destructive) { viewModel.clearLogbookAfterError() }
            Button("Cancel", role: .cancel) { viewModel.logbookLoadError = nil }
        } message: {
            Text(viewModel.logbookLoadError ?? "")
        }
    }

    // MARK: - Delete Handler

    private func deleteQSOs(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredQSOs[$0].id }
        idsToDelete.forEach { id in
            if let idx = viewModel.qsoList.firstIndex(where: { $0.id == id }) {
                viewModel.appLogger.log(
                    .info,
                    "Deleted QSO: \(viewModel.qsoList[idx].callsign) \(viewModel.qsoList[idx].grid)"
                )
                viewModel.qsoList.remove(at: idx)
            }
        }
    }

}

// MARK: - Preview

#Preview("LogbookView") {
    let vm = FT8ViewModel()
    vm.qsoList = PreviewMocks.qsoList
    return LogbookView()
        .environmentObject(vm)
}
