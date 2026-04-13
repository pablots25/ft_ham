//
//  StatisticsView.swift
//  ft_ham
//
//  Created by Copilot on 13/04/26.
//

import SwiftUI

struct StatisticsView: View {
    @StateObject private var vm: StatisticsViewModel

    init(entries: [LogEntry], myGrid: String = "") {
        _vm = StateObject(wrappedValue: StatisticsViewModel(entries: entries, myGrid: myGrid))
    }

    var body: some View {
        Group {
            if vm.summary.totalQSOs == 0 {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $vm.showCustomDatePicker) {
            customDateSheet
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: LayoutConstants.largeSpacing) {
                periodPicker

                StatsSummarySection(summary: vm.summary)

                StatsStreaksSection(
                    longestStreak: vm.summary.longestStreak,
                    currentStreak: vm.summary.currentStreak
                )

                StatsActivitySection(
                    series: vm.summary.activitySeries,
                    isDaily: StatisticsEngine.shouldUseDailyGranularity(vm.selectedPeriod)
                )

                StatsBandsSection(data: vm.summary.qsosByBand)

                StatsModeSection(data: vm.summary.qsosByMode)

                StatsContinentSection(data: vm.summary.qsosByContinent)

                StatsCountriesSection(data: vm.summary.qsosByCountry)

                StatsTimeOfDaySection(data: vm.summary.qsosByHour)

                StatsDayOfWeekSection(data: vm.summary.qsosByDayOfWeek)

                StatsBandHourHeatmapSection(data: vm.summary.bandHourHeatmap)

                StatsDistanceSection(
                    distanceStats: vm.summary.distanceStats,
                    bestDX: vm.summary.bestDX,
                    distanceByBand: vm.summary.distanceByBand
                )

                StatsGrowthCurvesSection(
                    countriesOverTime: vm.summary.countriesOverTime,
                    gridsOverTime: vm.summary.gridsOverTime,
                    callsignsOverTime: vm.summary.callsignsOverTime
                )

                StatsTopCallsignsSection(data: vm.summary.topCallsigns)

                StatsSignalSection(
                    buckets: vm.summary.snrBuckets,
                    avgSnr: vm.summary.avgSnrReceived
                )

                StatsSnrScatterSection(data: vm.summary.snrScatter)

                StatsRecordsSection(records: vm.summary.records)

                StatsYearOverYearSection(data: vm.summary.yearOverYear)

                StatsQSORateSection(data: vm.summary.qsoRate)

                StatsCQModifierSection(data: vm.summary.qsosByCQModifier)

                StatsGridHeatmapSection(data: vm.summary.gridFieldHeatmap)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StatisticsViewModel.presetPeriods, id: \.id) { period in
                    periodChip(period)
                }
                // Custom button
                Button {
                    vm.showCustomDatePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text("Custom")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCustomActive ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(isCustomActive ? .white : .primary)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
    }

    private func periodChip(_ period: StatsPeriod) -> some View {
        let isSelected = vm.selectedPeriod == period
        return Button {
            vm.selectedPeriod = period
        } label: {
            Text(period.label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private var isCustomActive: Bool {
        if case .custom = vm.selectedPeriod { return true }
        return false
    }

    // MARK: - Custom Date Sheet

    private var customDateSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Start Date", selection: $vm.customStartDate, displayedComponents: .date)
                DatePicker("End Date", selection: $vm.customEndDate, displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.showCustomDatePicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        vm.applyCustomRange()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Statistics Yet")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Complete some QSOs and come back\nto see your operating statistics.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}
