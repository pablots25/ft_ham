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
    
    @State private var selectedOption: ExportOption = .all
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    
    private var lastExportDate: Date? {
        guard lastExportTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: lastExportTimestamp)
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                    } header: {
                        Text("Date Range (UTC)")
                    } footer: {
                        Text("All QSOs between the selected dates will be exported")
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
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        exportLogs()
                    }
                    .disabled(filteredQSOCount() == 0)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ActivityViewController(activityItems: [url])
                }
            }
        }
    }
    
    private func filteredQSOCount() -> Int {
        let filtered = getFilteredQSOs()
        return filtered.count
    }
    
    private func getFilteredQSOs() -> [LogEntry] {
        switch selectedOption {
        case .all:
            return viewModel.qsoList
        case .dateRange:
            return viewModel.logbookManager.filterEntries(
                viewModel.qsoList,
                from: startDate,
                to: endDate
            )
        case .recent:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return viewModel.logbookManager.filterEntries(
                viewModel.qsoList,
                from: sevenDaysAgo,
                to: Date()
            )
        case .new:
            if let lastExport = lastExportDate {
                return viewModel.logbookManager.filterEntries(
                    viewModel.qsoList,
                    from: lastExport,
                    to: Date()
                )
            } else {
                // No previous export, return all
                return viewModel.qsoList
            }
        }
    }
    
    private func exportLogs() {
        let filtered = getFilteredQSOs()
        
        if let url = viewModel.logbookManager.exportToADIF(filtered) {
            exportURL = url
            showingShareSheet = true
            
            // Save timestamp of successful export
            lastExportTimestamp = Date().timeIntervalSince1970
            
            // Log analytics
            let exportType: String
            switch selectedOption {
            case .all: exportType = "all"
            case .recent: exportType = "recent"
            case .dateRange: exportType = "date_range"
            case .new: exportType = "new"
            }
            AnalyticsManager.shared.logADIFExport(qsoCount: filtered.count, exportType: exportType)
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
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview("ExportOptionsView") {
    ExportOptionsView()
        .environmentObject(FT8ViewModel(txMessages: PreviewMocks.txMessages, rxMessages: PreviewMocks.rxMessages))
}
