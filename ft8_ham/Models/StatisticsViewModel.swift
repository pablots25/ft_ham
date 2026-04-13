//
//  StatisticsViewModel.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import Foundation

@MainActor
final class StatisticsViewModel: ObservableObject {

    private let entries: [LogEntry]
    private let myGrid: String

    @Published var selectedPeriod: StatsPeriod = .allTime {
        didSet { recompute() }
    }

    @Published var showCustomDatePicker = false
    @Published var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var customEndDate = Date()

    @Published private(set) var summary: StatisticsSummary

    init(entries: [LogEntry], myGrid: String = "") {
        self.entries = entries
        self.myGrid = myGrid
        self.summary = StatisticsEngine.compute(entries: entries, period: .allTime, myGrid: myGrid)
    }

    func applyCustomRange() {
        selectedPeriod = .custom(customStartDate, customEndDate)
        showCustomDatePicker = false
    }

    private func recompute() {
        summary = StatisticsEngine.compute(entries: entries, period: selectedPeriod, myGrid: myGrid)
    }

    /// Presets for the period picker (excluding custom).
    static let presetPeriods: [StatsPeriod] = [
        .allTime, .thisYear, .thisMonth, .last30Days, .last7Days
    ]
}
