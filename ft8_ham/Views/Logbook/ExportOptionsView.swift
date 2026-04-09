//
//  ExportOptionsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/2/26.
//

import SwiftUI

enum ExportOption: String, CaseIterable, Identifiable {
    case all = "All Logs"
    case dateRange = "Date Range"
    case recent = "Recent (Last 7 Days)"
    case new = "New QSOs only"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .all:
            return "Export all QSOs from your logbook"
        case .dateRange:
            return "Select a custom date range to export"
        case .recent:
            return "Export only QSOs from the last 7 days"
        case .new:
            return "Export only new QSOs since last export"
        }
    }
}

struct ExportOptionsView: View {
    @EnvironmentObject var viewModel: FT8ViewModel
    @Environment(\.dismiss) var dismiss
    @AppStorage("lastSuccessfulExportDate") private var lastExportTimestamp: Double = 0

    /// When non-nil, export only these entries (from multi-select).
    var preselectedEntries: [LogEntry]?

    private var isPreselected: Bool { preselectedEntries != nil }
    
    @State private var selectedOption: ExportOption = .all
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var startTime: Date = Calendar(identifier: .gregorian).startOfDay(for: Date())
    @State private var endTime: Date = Date()
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var showExportError = false
    @State private var showExportSuccess = false
    @State private var exportedCount = 0
    @State private var isExporting = false
    
    @State private var didShare = false
    
    private var lastExportDate: Date? {
        guard lastExportTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: lastExportTimestamp)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if isPreselected {
                    preselectedContent
                } else {
                    standardContent
                }
            }
            .navigationTitle(isPreselected ? "Export Selected" : "Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton()
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Button("Export") {
                            exportLogs()
                        }
                        .disabled(filteredQSOCount() == 0)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: {
                if didShare {
                    showExportSuccess = true
                    didShare = false
                }
            }) {
                if let url = exportURL {
                    ActivityViewController(activityItems: [url], didShare: $didShare)
                }
            }
            .alert("Export Complete", isPresented: $showExportSuccess) {
                Button("OK") {}
            } message: {
                Text("\(exportedCount) QSO(s) exported successfully.")
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK") {}
            } message: {
                Text("The logbook could not be exported. Please try again.")
            }
        }
    }

    // MARK: - Preselected Content

    @ViewBuilder
    private var preselectedContent: some View {
        Section {
            HStack {
                Text("Selected QSOs")
                Spacer()
                Text("\(preselectedEntries?.count ?? 0)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Export Selection")
        }

        if let entries = preselectedEntries, !entries.isEmpty {
            Section {
                ForEach(entries.prefix(5), id: \.id) { entry in
                    HStack {
                        if let flag = entry.flag { Text(flag) }
                        Text(entry.callsign).fontWeight(.medium)
                        Spacer()
                        Text(entry.band)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(entry.mode)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                if entries.count > 5 {
                    Text("… and \(entries.count - 5) more")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } header: {
                Text("Preview")
            }
        }
    }

    // MARK: - Standard Content

    @ViewBuilder
    private var standardContent: some View {
        Section {
            Picker("Export Option", selection: $selectedOption) {
                ForEach(ExportOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("Select Export Type")
        }

        Section {
            Text(selectedOption.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if selectedOption == .new {
                if let lastExport = lastExportDate {
                    Text("Last export: \(formatDate(lastExport))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Text("No previous export found. All QSOs will be exported.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
        } header: {
            Text("Description")
        }

        if selectedOption == .dateRange {
            Section {
                DatePicker(
                    "Start Date",
                    selection: $startDate,
                    in: ...endDate,
                    displayedComponents: .date
                )

                DatePicker(
                    "End Date",
                    selection: $endDate,
                    in: startDate...Date(),
                    displayedComponents: .date
                )

                DatePicker(
                    "Start Time (UTC)",
                    selection: $startTime,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

                DatePicker(
                    "End Time (UTC)",
                    selection: $endTime,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            } header: {
                Text("Date & Time Range (UTC)")
            } footer: {
                Text("Only QSOs within the selected dates and UTC time window will be exported")
            }
        }

        Section {
            let count = filteredQSOCount()

            HStack {
                Text("QSOs to Export")
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Summary")
        }
    }
    
    private func filteredQSOCount() -> Int {
        let filtered = getFilteredQSOs()
        return filtered.count
    }
    
    private func getFilteredQSOs() -> [LogEntry] {
        if let entries = preselectedEntries {
            return entries
        }
        switch selectedOption {
        case .all:
            return viewModel.qsoList
        case .dateRange:
            var filtered = viewModel.logbookManager.filterEntries(
                viewModel.qsoList,
                from: startDate,
                to: endDate
            )
            // Apply UTC time-of-day window
            let utc = TimeZone(secondsFromGMT: 0)!
            let cal = Calendar(identifier: .gregorian)
            let startComps = cal.dateComponents(in: utc, from: startTime)
            let endComps = cal.dateComponents(in: utc, from: endTime)
            let startSec = (startComps.hour ?? 0) * 3600 + (startComps.minute ?? 0) * 60
            let endSec = (endComps.hour ?? 23) * 3600 + (endComps.minute ?? 59) * 60
            filtered = filtered.filter { entry in
                let c = cal.dateComponents(in: utc, from: entry.date)
                let s = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60
                return s >= startSec && s <= endSec
            }
            return filtered
        case .recent:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return viewModel.logbookManager.filterEntries(
                viewModel.qsoList,
                from: sevenDaysAgo,
                to: Date()
            )
        case .new:
            if let lastExport = lastExportDate {
                return viewModel.logbookManager.filterEntriesSince(viewModel.qsoList, since: lastExport, upTo: Date())
            } else {
                // No previous export, return all
                return viewModel.qsoList
            }
        }
    }
    
    private func exportLogs() {
        isExporting = true
        let filtered = getFilteredQSOs()
        
        if let url = viewModel.logbookManager.exportToADIF(filtered) {
            exportURL = url
            exportedCount = filtered.count
            isExporting = false
            showingShareSheet = true
            
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            // Save timestamp of successful export
            lastExportTimestamp = Date().timeIntervalSince1970
            
            // Log analytics
            let exportType: String
            if isPreselected {
                exportType = "selected"
            } else {
                switch selectedOption {
                case .all: exportType = "all"
                case .recent: exportType = "recent"
                case .dateRange: exportType = "date_range"
                case .new: exportType = "new"
                }
            }
            AnalyticsManager.shared.logADIFExport(qsoCount: filtered.count, exportType: exportType)
        } else {
            isExporting = false
            showExportError = true
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date) + " UTC"
    }
}

// Helper view for sharing
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    @Binding var didShare: Bool

    init(activityItems: [Any], didShare: Binding<Bool> = .constant(true)) {
        self.activityItems = activityItems
        self._didShare = didShare
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(didShare: $didShare)
    }
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            context.coordinator.didShare.wrappedValue = completed
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    
    class Coordinator {
        var didShare: Binding<Bool>
        init(didShare: Binding<Bool>) {
            self.didShare = didShare
        }
    }
}

#Preview("ExportOptionsView") {
    ExportOptionsView()
        .environmentObject(FT8ViewModel(txMessages: PreviewMocks.txMessages, rxMessages: PreviewMocks.rxMessages))
}
