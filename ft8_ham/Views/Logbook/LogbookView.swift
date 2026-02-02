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

    var body: some View {
        List {
            ForEach($viewModel.qsoList) { $entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.callsign)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(entry.grid)
                            .foregroundStyle(.secondary)

                        if let station = entry.stationCallsign, !station.isEmpty {
                            Text("Station: \(station)")
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
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.trailing, 5)

                            Text("\(entry.rstSent)")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("(TX)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(" / ")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Text("\(entry.rstRcvd)")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("(RX)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Mode: \(entry.mode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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

                    Text(entry.band)
                        .font(.caption)
                        .padding(6)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
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
        }
        .onAppear {
            sortQSOsByDate()
        }
        .onChange(of: viewModel.qsoList.count) { _ in
            sortQSOsByDate()
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
