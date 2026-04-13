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
    @State private var searchTask: Task<Void, Never>?

    // Delete confirmation
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var showDeleteConfirmation = false

    // Undo
    @State private var recentlyDeletedEntries: [(entry: LogEntry, index: Int)] = []
    @State private var showUndoBanner = false
    @State private var undoDismissTask: Task<Void, Never>?

    // Date range filter
    @State private var filterStartDate: Date?
    @State private var filterEndDate: Date?
    @State private var showDateFilter = false

    // Batch selection
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchDeleteConfirmation = false

    // Export & Clear
    @State private var showExportOptions = false
    @State private var showSelectionExport = false
    @State private var showClearLogbookAlert = false

    // Statistics
    @State private var showStatistics = false

    // MARK: - Filtering

    private func applyFilter() {
        var source = viewModel.sortedQSOList

        // Date range filter
        if let start = filterStartDate {
            source = source.filter { $0.date >= start }
        }
        if let end = filterEndDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            source = source.filter { $0.date < endOfDay }
        }

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
        ZStack(alignment: .bottom) {
            List(selection: isSelecting ? $selectedIDs : nil) {
                // Date range filter banner
                if filterStartDate != nil || filterEndDate != nil {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.blue)
                        if let start = filterStartDate, let end = filterEndDate {
                            Text("\(start, format: .dateTime.day().month().year()) – \(end, format: .dateTime.day().month().year())")
                                .font(.caption)
                        } else if let start = filterStartDate {
                            Text("From \(start, format: .dateTime.day().month().year())")
                                .font(.caption)
                        } else if let end = filterEndDate {
                            Text("Until \(end, format: .dateTime.day().month().year())")
                                .font(.caption)
                        }
                        Spacer()
                        Button {
                            filterStartDate = nil
                            filterEndDate = nil
                            applyFilter()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.blue.opacity(0.08))
                }

                ForEach(filteredQSOs) { entry in
                    LogbookRowCell(
                        entry: entry,
                        isExpanded: expandedIDs.contains(entry.id),
                        displayLocalTime: displayLocalTime,
                        onTap: {
                            guard !isSelecting else { return }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if expandedIDs.contains(entry.id) {
                                    expandedIDs.remove(entry.id)
                                } else {
                                    expandedIDs.insert(entry.id)
                                }
                            }
                        },
                        onEdit: { editingEntry = entry },
                        onDelete: {
                            confirmAndDeleteSingle(entry)
                        }
                    )
                    .tag(entry.id)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, isSelecting ? .constant(.active) : .constant(.inactive))
            .searchable(text: $searchText, prompt: "Callsign, grid, country, mode, band…")
            .refreshable { applyFilter() }
            .onChange(of: searchText) { _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    applyFilter()
                }
            }
            .onChange(of: viewModel.qsoList.count) { _ in applyFilter() }
            .onChange(of: viewModel.qsoList.first?.id) { _ in applyFilter() }
            .onAppear { applyFilter() }
            .overlay {
                if viewModel.qsoList.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Empty Logbook")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text("Completed QSOs will appear here.\nYou can also import from an ADIF file.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        Button {
                            showingImportSheet = true
                        } label: {
                            Label("Import ADIF", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(isSelecting ? selectionTitle : "Logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        HStack(spacing: 16) {
                            Button("Done") {
                                isSelecting = false
                                selectedIDs.removeAll()
                            }

                            Button {
                                if selectedIDs.count == filteredQSOs.count {
                                    selectedIDs.removeAll()
                                } else {
                                    selectedIDs = Set(filteredQSOs.map(\.id))
                                }
                            } label: {
                                Text(selectedIDs.count == filteredQSOs.count ? "Deselect All" : "Select All")
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button {
                            showSelectionExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(selectedIDs.isEmpty)
                    } else {
                        NavigationLink(destination: StatisticsView(entries: viewModel.qsoList)) {
                            Image(systemName: "chart.bar.xaxis")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        EmptyView()
                    } else {
                        Button {
                            showExportOptions = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(viewModel.qsoList.isEmpty)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(role: .destructive) {
                            showBatchDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedIDs.isEmpty)
                    } else {
                        Button {
                            isSelecting = true
                        } label: {
                            Image(systemName: "checkmark.circle")
                        }
                        .disabled(viewModel.qsoList.isEmpty)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        EmptyView()
                    } else {
                        Menu {
                            Button {
                                showingImportSheet = true
                            } label: {
                                Label("Import ADIF", systemImage: "square.and.arrow.down")
                            }

                            Divider()

                            Button {
                                displayLocalTime.toggle()
                            } label: {
                                Label(
                                    displayLocalTime ? "Switch to UTC" : "Switch to Local Time",
                                    systemImage: "clock"
                                )
                            }

                            Button {
                                showDateFilter = true
                            } label: {
                                Label("Filter by Date", systemImage: "calendar")
                            }

                            Divider()

                            Button(role: .destructive) {
                                showClearLogbookAlert = true
                            } label: {
                                Label("Clear Logbook", systemImage: "trash")
                            }
                            .disabled(viewModel.qsoList.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }

            // Undo banner
            if showUndoBanner, !recentlyDeletedEntries.isEmpty {
                undoBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterView(
                startDate: $filterStartDate,
                endDate: $filterEndDate,
                onApply: { applyFilter() }
            )
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
        .alert("Delete QSO?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    deleteQSOs(at: offsets)
                    pendingDeleteOffsets = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteOffsets = nil
            }
        } message: {
            if let offsets = pendingDeleteOffsets {
                let count = offsets.count
                Text(count == 1
                     ? "This QSO will be permanently deleted."
                     : "\(count) QSOs will be permanently deleted.")
            }
        }
        .alert("Delete \(selectedIDs.count) QSO\(selectedIDs.count == 1 ? "" : "s")?", isPresented: $showBatchDeleteConfirmation) {
            Button("Delete", role: .destructive) { batchDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showExportOptions) {
            ExportOptionsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showSelectionExport) {
            ExportOptionsView(preselectedEntries: selectedEntries)
                .environmentObject(viewModel)
        }
        .alert("Clear logbook?", isPresented: $showClearLogbookAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.clearLogbookConfirmed()
            }
        } message: {
            Text("This will permanently delete all QSOs.")
        }
    }

    // MARK: - Undo Banner

    private var undoBanner: some View {
        let count = recentlyDeletedEntries.count
        return HStack {
            Text(count == 1 ? "QSO deleted" : "\(count) QSOs deleted")
                .font(.subheadline)
            Spacer()
            Button("Undo") {
                undoDelete()
            }
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Delete Confirmation

    private func confirmAndDeleteSingle(_ entry: LogEntry) {
        if let idx = filteredQSOs.firstIndex(where: { $0.id == entry.id }) {
            pendingDeleteOffsets = IndexSet(integer: idx)
            showDeleteConfirmation = true
        }
    }

    // MARK: - Delete Handler

    private func deleteQSOs(at offsets: IndexSet) {
        undoDismissTask?.cancel()
        var deleted: [(entry: LogEntry, index: Int)] = []

        let idsToDelete = offsets.map { filteredQSOs[$0].id }
        for id in idsToDelete {
            if let idx = viewModel.qsoList.firstIndex(where: { $0.id == id }) {
                let entry = viewModel.qsoList[idx]
                deleted.append((entry: entry, index: idx))
                viewModel.appLogger.log(
                    .info,
                    "Deleted QSO: \(entry.callsign) \(entry.grid)"
                )
                viewModel.qsoList.remove(at: idx)
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if !deleted.isEmpty {
            recentlyDeletedEntries = deleted
            withAnimation { showUndoBanner = true }
            undoDismissTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation {
                    showUndoBanner = false
                    recentlyDeletedEntries.removeAll()
                }
            }
        }
    }

    // MARK: - Undo

    private func undoDelete() {
        undoDismissTask?.cancel()
        for item in recentlyDeletedEntries.reversed() {
            let safeIndex = min(item.index, viewModel.qsoList.count)
            viewModel.qsoList.insert(item.entry, at: safeIndex)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation {
            showUndoBanner = false
            recentlyDeletedEntries.removeAll()
        }
    }

    // MARK: - Selection Title

    private var selectionTitle: String {
        selectedIDs.isEmpty
            ? "Select Items"
            : "\(selectedIDs.count) Selected"
    }

    // MARK: - Batch Delete

    private var selectedEntries: [LogEntry] {
        viewModel.qsoList.filter { selectedIDs.contains($0.id) }
    }

    private func batchDelete() {
        undoDismissTask?.cancel()
        var deleted: [(entry: LogEntry, index: Int)] = []

        for id in selectedIDs {
            if let idx = viewModel.qsoList.firstIndex(where: { $0.id == id }) {
                let entry = viewModel.qsoList[idx]
                deleted.append((entry: entry, index: idx))
            }
        }
        // Sort by descending index so removal doesn't shift subsequent indices
        deleted.sort { $0.index > $1.index }
        for item in deleted {
            viewModel.qsoList.remove(at: item.index)
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        selectedIDs.removeAll()
        isSelecting = false

        if !deleted.isEmpty {
            recentlyDeletedEntries = deleted
            withAnimation { showUndoBanner = true }
            undoDismissTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation {
                    showUndoBanner = false
                    recentlyDeletedEntries.removeAll()
                }
            }
        }
    }
}

// MARK: - Date Range Filter Sheet

struct DateRangeFilterView: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var localStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var localEnd: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $localStart, in: ...localEnd, displayedComponents: .date)
                    DatePicker("To", selection: $localEnd, in: localStart...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Filter by Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        startDate = localStart
                        endDate = localEnd
                        onApply()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let s = startDate { localStart = s }
                if let e = endDate { localEnd = e }
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
