//
//  LogsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 30/12/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct LogsView: View {
    @StateObject private var store = LogStore.shared
    @State private var showingShareSheet = false
    @State private var logFileURL: URL?
    @State private var selectedFilter: LogLevelFilter = .all
    @State private var searchText: String = ""
    @State private var cachedFilteredLogs: [String] = []
    
    // States for loading and error management
    @State private var isExporting = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    enum LogLevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case info = "INFO"
        case debug = "DEBUG"
        case warning = "WARNING"
        case error = "ERROR"

        var id: String { rawValue }
    }

    var filteredLogs: [String] {
        let levelFiltered: [String]
        switch selectedFilter {
        case .all:     levelFiltered = store.logs
        case .info:    levelFiltered = store.logs.filter { $0.contains("[INFO]") }
        case .debug:   levelFiltered = store.logs.filter { $0.contains("[DEBUG]") }
        case .warning: levelFiltered = store.logs.filter { $0.contains("[WARNING]") }
        case .error:   levelFiltered = store.logs.filter { $0.contains("[ERROR]") }
        }
        guard !searchText.isEmpty else { return levelFiltered }
        return levelFiltered.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            VStack {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(LogLevelFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(cachedFilteredLogs.indices, id: \.self) { idx in
                            Text(cachedFilteredLogs[idx])
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(color(for: cachedFilteredLogs[idx]))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(idx % 2 == 0 ? Color(.systemGray6) : Color(.systemGray5))
                                .cornerRadius(4)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("System Logs")
            .disabled(isExporting)
            .blur(radius: isExporting ? 2 : 0)

            // Loading overlay
            if isExporting {
                ZStack {
                    Color(.separator).opacity(0.15)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 15) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.primary)
                        Text("Preparing logs...")
                            .font(.headline)
                    }
                    .padding(40)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                }
                .transition(.opacity)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter logs…")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.clear() } label: {
                    Image(systemName: "trash")
                }
                .disabled(isExporting)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportLogs) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(isExporting || cachedFilteredLogs.isEmpty)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = logFileURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .alert("Export Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            cachedFilteredLogs = filteredLogs
        }
        .onChange(of: selectedFilter) { _ in
            cachedFilteredLogs = filteredLogs
        }
        .onChange(of: searchText) { _ in
            cachedFilteredLogs = filteredLogs
        }
        .onChange(of: store.logs) { _ in
            cachedFilteredLogs = filteredLogs
        }
    }

    private func exportLogs() {
        isExporting = true
        
        // Background thread to handle heavy string joining and file writing
        DispatchQueue.global(qos: .userInitiated).async {
            let filename = "ft8_ham_logs_\(Int(Date().timeIntervalSince1970)).txt"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                let content = self.cachedFilteredLogs.joined(separator: "\n")
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                DispatchQueue.main.async {
                    self.logFileURL = fileURL
                    self.isExporting = false
                    self.showingShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isExporting = false
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func color(for logLine: String) -> Color {
        if logLine.contains("[ERROR]") {
            return .red
        } else if logLine.contains("[WARNING]") {
            return .orange
        } else if logLine.contains("[DEBUG]") {
            return .gray
        } else {
            return .primary
        }
    }
}
