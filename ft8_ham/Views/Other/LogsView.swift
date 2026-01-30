//
//  LogsView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 30/12/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct LogsView: View {
    @ObservedObject private var store = LogStore.shared
    @State private var showingShareSheet = false
    @State private var logFileURL: URL?
    @State private var selectedFilter: LogLevelFilter = .all
    
    // States for loading and error management
    @State private var isExporting = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    enum LogLevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case info = "INFO"
        case debug = "DEBUG"
        case error = "ERROR"

        var id: String { rawValue }
    }

    var filteredLogs: [String] {
        switch selectedFilter {
        case .all: return store.logs
        case .info: return store.logs.filter { $0.contains("[INFO]") }
        case .debug: return store.logs.filter { $0.contains("[DEBUG]") }
        case .error: return store.logs.filter { $0.contains("[ERROR]") }
        }
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
                        ForEach(filteredLogs.indices, id: \.self) { idx in
                            Text(filteredLogs[idx])
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(color(for: filteredLogs[idx]))
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
                    Color.black.opacity(0.15)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") { store.clear() }
                .disabled(isExporting)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportLogs) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(isExporting || filteredLogs.isEmpty)
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
    }

    private func exportLogs() {
        isExporting = true
        
        // Background thread to handle heavy string joining and file writing
        DispatchQueue.global(qos: .userInitiated).async {
            let filename = "ft8_ham_logs_\(Int(Date().timeIntervalSince1970)).txt"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                let content = self.filteredLogs.joined(separator: "\n")
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
        } else if logLine.contains("[DEBUG]") {
            return .gray
        } else {
            return .primary
        }
    }
}

// MARK: - Activity View Wrapper
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
