//
//  QSOEditView.swift
//  ft_ham
//
//  Created by GitHub Copilot on 6/4/26.
//

import SwiftUI

struct QSOEditView: View {
    let entry: LogEntry
    let onSave: (LogEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Draft fields

    @State private var callsign: String
    @State private var grid: String
    @State private var date: Date
    @State private var frequencyMHz: String
    @State private var mode: String
    @State private var band: String
    @State private var rstSent: String
    @State private var rstRcvd: String
    @State private var stationCallsign: String
    @State private var cqModifier: String
    @State private var mySigInfo: String
    @State private var showDiscardAlert = false

    private let modes = ["FT8", "FT4"]
    private let bands: [String] = FT8Message.Band.allCases
        .filter { $0 != .unknown }
        .map(\.rawValue)

    // MARK: - Init

    init(entry: LogEntry, onSave: @escaping (LogEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave

        _callsign       = State(initialValue: entry.callsign)
        _grid           = State(initialValue: entry.grid)
        _date           = State(initialValue: entry.date)
        _frequencyMHz   = State(initialValue: entry.frequencyHz.map { String(format: "%.6f", $0 / 1_000_000) } ?? "")
        _mode           = State(initialValue: entry.mode.isEmpty ? "FT8" : entry.mode)
        _band           = State(initialValue: entry.band)
        _rstSent        = State(initialValue: entry.rstSent)
        _rstRcvd        = State(initialValue: entry.rstRcvd)
        _stationCallsign = State(initialValue: entry.stationCallsign ?? "")
        _cqModifier     = State(initialValue: entry.cqModifier ?? "")
        _mySigInfo      = State(initialValue: entry.mySigInfo ?? "")
    }

    // MARK: - Validation

    private var gridValidationMessage: String? {
        let trimmed = grid.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"^[A-R]{2}\d{2}([A-X]{2}(\d{2})?)?$"#
        if trimmed.range(of: pattern, options: .regularExpression) == nil {
            return "Invalid Maidenhead grid (e.g. EM72 or EM72ab)"
        }
        return nil
    }

    private var bandFrequencyMismatch: String? {
        let clean = frequencyMHz.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, let mhz = Double(clean), mhz > 0 else { return nil }
        let detectedBand = FT8Message.Band.fromFrequency(mhz * 1_000_000)
        guard detectedBand != .unknown else { return nil }
        if let selectedBand = FT8Message.Band(rawValue: band),
           selectedBand != detectedBand {
            return "Frequency corresponds to \(detectedBand.rawValue), not \(band)"
        }
        return nil
    }

    private var hasChanges: Bool {
        callsign != entry.callsign ||
        grid != entry.grid ||
        date != entry.date ||
        frequencyMHz != (entry.frequencyHz.map { String(format: "%.6f", $0 / 1_000_000) } ?? "") ||
        mode != (entry.mode.isEmpty ? "FT8" : entry.mode) ||
        band != entry.band ||
        rstSent != entry.rstSent ||
        rstRcvd != entry.rstRcvd ||
        stationCallsign != (entry.stationCallsign ?? "") ||
        cqModifier != (entry.cqModifier ?? "") ||
        mySigInfo != (entry.mySigInfo ?? "")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Callsign") {
                        TextField("e.g. W1ABC", text: $callsign)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }

                    LabeledContent("Grid") {
                        TextField("e.g. EM72", text: $grid)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }

                    LabeledContent("Station Callsign") {
                        TextField("Optional", text: $stationCallsign)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Station")
                } footer: {
                    if let msg = gridValidationMessage {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    DatePicker("Date & Time (UTC)", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

                    Picker("Mode", selection: $mode) {
                        ForEach(modes, id: \.self) { Text($0) }
                    }

                    Picker("Band", selection: $band) {
                        ForEach(bands, id: \.self) { Text($0) }
                    }

                    LabeledContent("Frequency (MHz)") {
                        TextField("e.g. 14.074000", text: $frequencyMHz)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("QSO")
                } footer: {
                    if let msg = bandFrequencyMismatch {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                Section("Signal Report") {
                    LabeledContent("RST Sent") {
                        TextField("e.g. -10", text: $rstSent)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("RST Received") {
                        TextField("e.g. -05", text: $rstRcvd)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Activation") {
                    LabeledContent("CQ Modifier") {
                        TextField("e.g. POTA", text: $cqModifier)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }

                    LabeledContent("Reference") {
                        TextField("e.g. K-1234", text: $mySigInfo)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle("Edit QSO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if hasChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(callsign.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("You have unsaved changes that will be lost.")
            }
            .onChange(of: band) { _ in autoFillFrequency() }
            .onChange(of: mode) { _ in autoFillFrequency() }
        }
    }

    // MARK: - Auto-fill frequency from band + mode

    private func autoFillFrequency() {
        // Only auto-fill when the frequency field is empty
        guard frequencyMHz.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let selectedBand = FT8Message.Band(rawValue: band) else { return }
        let ft8mode: FT8Message.FT8MessageMode = mode == "FT4" ? .ft4 : .ft8
        guard let hz = selectedBand.frequency(for: ft8mode) else { return }
        frequencyMHz = String(format: "%.6f", hz / 1_000_000)
    }

    // MARK: - Save

    private func saveAndDismiss() {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let normalizedGrid = grid.trimmingCharacters(in: .whitespaces).uppercased()

        let freqHz: Double? = {
            let clean = frequencyMHz.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, let mhz = Double(clean), mhz > 0 else { return nil }
            return mhz * 1_000_000
        }()

        let country = CountryResolver.countryAndCoordinates(for: normalizedCallsign).country
        let flag = FlagUtility.flag(for: country)

        let updated = LogEntry(
            id: entry.id,
            callsign: normalizedCallsign,
            grid: normalizedGrid,
            date: date,
            frequencyHz: freqHz,
            mode: mode,
            band: band,
            rstSent: rstSent.trimmingCharacters(in: .whitespaces),
            rstRcvd: rstRcvd.trimmingCharacters(in: .whitespaces),
            stationCallsign: stationCallsign.isEmpty ? nil : stationCallsign.uppercased(),
            cqModifier: cqModifier.isEmpty ? nil : cqModifier.uppercased(),
            mySigInfo: mySigInfo.isEmpty ? nil : mySigInfo.uppercased(),
            country: country,
            flag: flag,
            qrzStatus: entry.qrzStatus,
            lotwStatus: entry.lotwStatus
        )

        onSave(updated)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
