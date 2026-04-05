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

    var body: some View {
        List {
            ForEach($viewModel.qsoList) { $entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.callsign)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if let flag = entry.flag {
                                Text(flag)
                                    .font(.headline)
                            }

                            if let country = entry.country, !country.isEmpty {
                                Text(country)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Text(entry.grid)
                            .foregroundStyle(.primary)

                        if let station = entry.stationCallsign, !station.isEmpty {
                            Text("Station: \(station)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let hz = entry.frequencyHz {
                            Text(String(format: "%.3f MHz", hz / 1_000_000))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let cqModifier = entry.cqModifier, !cqModifier.isEmpty {
                            if let sigInfo = entry.mySigInfo, !sigInfo.isEmpty {
                                Text("\(cqModifier): \(sigInfo)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(cqModifier)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("SNR:")
                                .font(.caption)
                                .foregroundStyle(.primary)

                            Text("\(entry.rstSent)")
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text("(TX)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("/")
                                .font(.caption)
                                .foregroundStyle(.primary)

                            Text("\(entry.rstRcvd)")
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text("(RX)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)

                        Text(dateFormatter.string(from: entry.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 1) {
                            Text(timeFormatter.string(from: entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if displayLocalTime {
                                Text("(Local)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        if !entry.mode.isEmpty {
                            Text(entry.mode)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .padding(6)
                                .background(modeColor(entry.mode).opacity(0.2))
                                .cornerRadius(6)
                        }
                        if entry.band != "Unknown" && !entry.band.isEmpty {
                            Text(entry.band)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .padding(6)
                                .background(bandColor(entry.band).opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            .onDelete(perform: deleteQSOs)
        }
        .listStyle(.plain)
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
            ToolbarItem(placement: .automatic) {
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

            ToolbarItem(placement: .automatic) {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Import ADIF", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("Import QSOs from ADIF file")
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            LogbookImportView()
                .environmentObject(viewModel)
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
        .onAppear {
            sortQSOsByDate()
        }
        .onChange(of: viewModel.qsoList.count) { _ in
            sortQSOsByDate()
        }
    }

    // MARK: - Badge Colors

    private func modeColor(_ mode: String) -> Color {
        switch mode.uppercased() {
        case "FT8":  return .green
        case "FT4":  return .blue
        default:     return .gray
        }
    }

    private func bandColor(_ band: String) -> Color {
        switch band {
        case "160m":    return .purple
        case "80m":     return Color(red: 0.5, green: 0.0, blue: 0.5)  // dark purple
        case "60m":     return .indigo
        case "40m":     return .blue
        case "30m":     return .teal
        case "20m":     return .green
        case "17m":     return .cyan
        case "15m":     return .yellow
        case "12m":     return .orange
        case "CB/11m":  return .gray
        case "10m":     return .red
        case "6m":      return .pink
        case "Custom":  return .mint
        default:        return .blue
        }
    }

    // MARK: - Sorting

    private func sortQSOsByDate() {
        viewModel.qsoList.sort { lhs, rhs in
            lhs.date > rhs.date
        }
    }

    // MARK: - Delete Handler

    private func deleteQSOs(at offsets: IndexSet) {
        offsets.forEach { index in
            let removed = viewModel.qsoList[index]
            viewModel.appLogger.log(
                .info,
                "Deleted QSO: \(removed.callsign) \(removed.grid)"
            )
        }
        viewModel.qsoList.remove(atOffsets: offsets)
    }

    // MARK: - Date / Time Formatters (UI only)

    private var activeTimeZone: TimeZone {
        displayLocalTime ? .current : TimeZone(secondsFromGMT: 0)!
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = activeTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = activeTimeZone
        formatter.dateFormat = displayLocalTime
            ? "HH:mm:ss"
            : "HH:mm:ss 'UTC'"
        return formatter
    }
}

// MARK: - Preview

#Preview("LogbookView") {
    let vm = FT8ViewModel()
    vm.qsoList = PreviewMocks.qsoList
    return LogbookView()
        .environmentObject(vm)
}
