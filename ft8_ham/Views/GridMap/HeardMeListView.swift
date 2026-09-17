//
//  HeardMeListView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import SwiftUI

/// Sheet listing the stations that heard us, nearest first.
struct HeardMeListView: View {
    @ObservedObject var store: HeardMeStore
    let myCallsign: String
    let myLocator: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.stations.isEmpty {
                        Text(store.lastFetch == nil ? "Not fetched yet" : "Nobody reported hearing you in this window")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.stations) { station in
                            row(station)
                        }
                    }
                } header: {
                    HStack {
                        Text("Stations that heard you")
                        Spacer()
                        Text("\(store.stations.count)")
                            .monospacedDigit()
                    }
                } footer: {
                    footer
                }
            }
            .listStyle(.plain)
            .navigationTitle("Heard me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Window", selection: Binding(
                        get: { store.window },
                        set: { store.window = $0 }
                    )) {
                        ForEach(HeardMeWindow.allCases) { window in
                            Text(window.title).tag(window)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                refreshButton
                    .padding()
                    .background(.thinMaterial)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ station: HeardMeStation) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.callsign)
                    .font(.body.monospaced())
                Text(station.locator)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let km = station.distanceKm {
                    Text("\(Int(km.rounded())) km")
                        .font(.body.monospacedDigit())
                }
                HStack(spacing: 6) {
                    if let snr = station.bestSNR {
                        Text(String(format: "%+d dB", snr))
                            .foregroundStyle(snr >= 0 ? .green : .secondary)
                    }
                    Text(station.lastHeard, style: .relative)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = store.lastError {
                Text(error).foregroundStyle(.orange)
            }
            if let date = store.lastFetch {
                Text(String(format: String(localized: "Last sync %@"), date.formatted(date: .omitted, time: .shortened)))
            }
            Text("Data from pskreporter.info. Stations report what they decode, so you only appear here after transmitting.")
        }
    }

    private var refreshButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let wait = store.secondsUntilNextFetch
            Button {
                Task { await store.refresh(callsign: myCallsign, myLocator: myLocator) }
            } label: {
                if store.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if wait > 0 {
                    Text(String(format: String(localized: "Next refresh in %@"), HeardMeStore.format(wait)))
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading || wait > 0)
            .accessibilityLabel(Text("Refresh"))
            .accessibilityIdentifier("button_heardMeRefresh")
        }
    }
}
