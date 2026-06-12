//
//  StatisticsView.swift
//  ft_ham
//
//  Wrapper that bridges LogEntry → StatisticsQSO and delegates
//  to FTHamPremium.StatisticsView.
//

import SwiftUI

#if canImport(FTHamPremium)
import FTHamPremium

struct StatisticsView: View {
    private let entries: [LogEntry]
    private let myGrid: String

    init(entries: [LogEntry], myGrid: String = "") {
        self.entries = entries
        self.myGrid = myGrid
    }

    var body: some View {
        FTHamPremium.StatisticsView(
            entries: entries.map { $0.toStatisticsQSO() },
            myGrid: myGrid
        )
    }
}

private extension LogEntry {
    func toStatisticsQSO() -> StatisticsQSO {
        StatisticsQSO(
            id: id,
            callsign: callsign,
            grid: grid,
            date: date,
            frequencyHz: frequencyHz,
            mode: mode,
            band: band,
            rstSent: rstSent,
            rstRcvd: rstRcvd,
            stationCallsign: stationCallsign,
            cqModifier: cqModifier,
            mySigInfo: mySigInfo,
            country: country,
            flag: flag
        )
    }
}
#else
struct StatisticsView: View {
    init(entries: [LogEntry], myGrid: String = "") {}

    var body: some View {
        StatisticsViewStub()
    }
}
#endif
