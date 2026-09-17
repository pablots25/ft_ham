//
//  LogEntry+CloudSync.swift
//  ft_ham
//
//  Created by Pablo Turrion on 14/09/26.
//

import Foundation

extension LogEntry {

    /// Stable identity of a QSO across devices, used as the CloudKit record
    /// name so the same contact logged twice collapses into one record.
    ///
    /// Minute resolution: two devices logging the same QSO stamp it within a
    /// second or two of each other, but can still straddle a minute boundary —
    /// the ±120 s rule in `LogbookManager.isDuplicate` catches that case when
    /// the records are merged locally.
    var dedupKey: String {
        let timestamp = LogEntry.dedupFormatter.string(from: date)
        return "\(callsign.uppercased())|\(band)|\(mode)|\(timestamp)"
    }

    private static let dedupFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var cloudRecord: CloudLogRecord {
        CloudLogRecord(
            dedupKey: dedupKey,
            sourceID: id.uuidString,
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
            flag: flag,
            qrzStatusRaw: qrzStatus.rawValue,
            lotwStatusRaw: lotwStatus.rawValue
        )
    }

    /// Rebuilds a local entry from a cloud record. The QRZ/LoTW pending sets
    /// are keyed by the local `id`, so a pulled entry gets a fresh one.
    init(cloud: CloudLogRecord) {
        self.init(
            callsign: cloud.callsign,
            grid: cloud.grid,
            date: cloud.date,
            frequencyHz: cloud.frequencyHz,
            mode: cloud.mode,
            band: cloud.band,
            rstSent: cloud.rstSent,
            rstRcvd: cloud.rstRcvd,
            stationCallsign: cloud.stationCallsign,
            cqModifier: cloud.cqModifier,
            mySigInfo: cloud.mySigInfo,
            country: cloud.country,
            flag: cloud.flag,
            qrzStatus: LogSyncStatus(rawValue: cloud.qrzStatusRaw) ?? .notUploaded,
            lotwStatus: LogSyncStatus(rawValue: cloud.lotwStatusRaw) ?? .notUploaded
        )
    }
}
