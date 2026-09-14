//
//  ICloudSyncSettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//
//  Lives in the app (not the premium package) because everything it shows
//  comes from `CloudLogbookSyncManager`, which owns LogEntry. Only the
//  CloudKit transport behind it is proprietary.
//

import SwiftUI

struct ICloudSyncSettingsView: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @ObservedObject private var sync = CloudLogbookSyncManager.shared
    @State private var activeHelp: HelpTip?
    @State private var showDeleteConfirm = false

    var body: some View {
        SettingsScrollContainer(title: "iCloud Sync", spacing: 20, dismissKeyboardOnScroll: false) {
            VStack(alignment: .leading, spacing: 14) {
                ToggleRow(
                    labelKey: "Sync logbook with iCloud",
                    helpTip: .iCloudSync,
                    isOn: Binding(
                        get: { sync.isEnabled },
                        set: { sync.isEnabled = $0 }
                    ),
                    activeHelp: $activeHelp
                )
                .disabled(sync.accountStatus != .available && !sync.isEnabled)
                .accessibilityIdentifier("toggle_iCloudLogbookSync")

                accountRow

                if sync.isEnabled {
                    Divider()
                    statusRow
                    actionButtons
                }

                Divider()

                Text("Your QSOs are stored in your own private iCloud database. Nobody else can read them, and they do not count towards the app's servers — only your iCloud storage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await sync.refreshAccountStatus() }
        .confirmationDialog(
            "Delete the iCloud copy of your logbook?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete iCloud copy", role: .destructive) {
                Task { await sync.deleteAllRemote() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The QSOs on this device are not touched. Other devices keep whatever they already downloaded.")
        }
    }

    @ViewBuilder
    private var accountRow: some View {
        switch sync.accountStatus {
        case .available:
            Label("iCloud account available", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .noAccount:
            Label("No iCloud account. Sign in from the Settings app to sync.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .restricted:
            Label("iCloud is restricted on this device.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = sync.lastError {
                Text(error)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            } else if let date = sync.lastSyncDate {
                Text(String(
                    format: String(localized: "Last sync %@"),
                    date.formatted(date: .omitted, time: .shortened)
                ))
            } else {
                Text("Not synced yet")
                    .foregroundStyle(.secondary)
            }

            if !sync.pendingKeys.isEmpty {
                Text(String(format: String(localized: "%d QSO(s) waiting to upload"), sync.pendingKeys.count))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await sync.pull()
                    await sync.pushPending()
                }
            } label: {
                if sync.isSyncing {
                    ProgressView()
                } else {
                    Text("Sync now")
                }
            }
            .buttonStyle(.bordered)
            .disabled(sync.isSyncing)
            .accessibilityIdentifier("button_iCloudSyncNow")

            Button {
                Task { await sync.pushAll() }
            } label: {
                Text(String(format: String(localized: "Upload all (%d)"), viewModel.qsoList.count))
            }
            .buttonStyle(.bordered)
            .disabled(sync.isSyncing || viewModel.qsoList.isEmpty)
            .accessibilityIdentifier("button_iCloudUploadAll")
        }

        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("Delete iCloud copy")
        }
        .buttonStyle(.bordered)
        .disabled(sync.isSyncing)
        .accessibilityIdentifier("button_iCloudDeleteRemote")
    }
}
