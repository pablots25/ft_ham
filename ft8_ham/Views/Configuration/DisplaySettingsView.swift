//
//  DisplaySettingsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import SwiftUI
import UserNotifications

/// How decoded traffic is presented and how the operator interacts with it.
/// Nothing here changes what the app transmits.
struct DisplaySettingsContent: View {
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var activeHelp: HelpTip?
    @AppStorage("replyTapGesture") private var replyTapGesture: ReplyTapGesture = .single
    @AppStorage(StatisticsHourFormat.storageKey) private var statisticsHourFormat: StatisticsHourFormat = .twentyFourHour
    @State private var notificationsDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Message List")
                .font(.headline)

            VStack {
                Text("View mode:")
                Picker("View mode", selection: Binding(
                    get: { viewModel.selectedViewMode },
                    set: { newMode in
                        viewModel.selectedViewMode = newMode
                        AnalyticsManager.shared.trackViewMode(newMode)
                    }
                )) {
                    ForEach(ViewMode.allCases) { mode in
                        if !mode.isIPadOnly || UIDevice.current.userInterfaceIdiom == .pad {
                            Text(mode.textKey).tag(mode)
                        }
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("Choose how the TX/RX message list is displayed.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ToggleRow(
                labelKey: "Show TX messages in RX list",
                helpTip: .decodeSelfTX,
                isOn: $viewModel.decodeSelfTXMessages,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_decodeSelfTXMessages")

            ToggleRow(
                labelKey: "Highlight new callsigns",
                helpTip: .highlightNewCallsigns,
                isOn: $viewModel.highlightNewCallsigns,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_highlightNewCallsigns")

            ToggleRow(
                labelKey: "Show NEW GRID badge",
                helpTip: .neededBadges,
                isOn: $viewModel.showNeededGridBadge,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_showNeededGridBadge")

            ToggleRow(
                labelKey: "Show NEW DXCC badge",
                helpTip: .neededBadges,
                isOn: $viewModel.showNeededDXCCBadge,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_showNeededDXCCBadge")

            Divider()

            Text("Calls to Me")
                .font(.headline)

            ToggleRow(
                labelKey: "Highlight calls to me",
                helpTip: .highlightMyCallsign,
                isOn: $viewModel.highlightMyCallsign,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_highlightMyCallsign")

            Divider()

            Text("Watched Stations")
                .font(.headline)

            Text("Stations to spot in the RX list, such as a DXpedition. Their messages get their own color and a star.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            WatchListEditor()

            ToggleRow(
                labelKey: "Alert when a watched station is heard",
                helpTip: .watchAlert,
                isOn: $viewModel.watchAlertEnabled,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_watchAlertEnabled")

            Divider()

            Text("Alerts")
                .font(.headline)

            ToggleRow(
                labelKey: "Play a sound",
                helpTip: .callAlertSound,
                isOn: $viewModel.callAlertSound,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_callAlertSound")

            ToggleRow(
                labelKey: "Vibrate",
                helpTip: .callAlertHaptic,
                isOn: $viewModel.callAlertHaptic,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_callAlertHaptic")

            ToggleRow(
                labelKey: "Show a notification",
                helpTip: .callAlertNotification,
                isOn: $viewModel.callAlertNotification,
                activeHelp: $activeHelp
            )
            .accessibilityIdentifier("toggle_callAlertNotification")

            if viewModel.callAlertNotification && notificationsDenied {
                Text("Notifications are turned off for FT Ham. Turn them on in the Settings app.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Text("Alerts fire when a station calls you and no QSO is in progress, and when a watched station is heard, at most once every 10 minutes per station. They work while the app is open, because reception pauses in the background.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("The sound stays muted when audio goes to a USB or line interface, so it never reaches the radio.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            DisclosureGroup {
                MessageColorSettings()
            } label: {
                Text("Message Colors")
                    .font(.headline)
            }
            .accessibilityIdentifier("disclosure_messageColors")

            Divider()

            Text("Interaction")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reply gesture")
                Picker("Reply gesture", selection: $replyTapGesture) {
                    ForEach(ReplyTapGesture.allCases) { gesture in
                        Text(gesture.label).tag(gesture)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("picker_replyTapGesture")

                Text("How tapping a decoded caller starts a reply. Double tap helps avoid accidental replies.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Statistics")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hour format")
                Picker("Hour format", selection: $statisticsHourFormat) {
                    ForEach(StatisticsHourFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("picker_statisticsHourFormat")

                Text("How hours are labeled in the Statistics charts. Hours are always UTC.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { activeHelp = nil }
        .task { await refreshNotificationStatus(requestIfNeeded: false) }
        .onChange(of: viewModel.callAlertNotification) { isOn in
            guard isOn else { return }
            Task { await refreshNotificationStatus(requestIfNeeded: true) }
        }
    }

    /// Asks for notification permission the first time the alert is turned on
    /// and remembers whether the user has turned notifications off.
    private func refreshNotificationStatus(requestIfNeeded: Bool) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined && requestIfNeeded {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        notificationsDenied = status == .denied
    }
}

struct DisplaySettingsView: View {
    var body: some View {
        SettingsScrollContainer(title: "Display", alignment: .leading, spacing: 10) {
            DisplaySettingsContent()
        }
    }
}

#Preview {
    NavigationStack {
        DisplaySettingsView()
            .environmentObject(FT8ViewModel(
                txMessages: PreviewMocks.txMessages,
                rxMessages: PreviewMocks.rxMessages
            ))
    }
}
