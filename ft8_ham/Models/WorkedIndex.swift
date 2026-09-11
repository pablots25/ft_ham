//
//  WorkedIndex.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation

/// Per band/mode lookup tables derived from the logbook.
///
/// Rebuilt from `qsoList` whenever it changes so the decode list can answer
/// "is this station / grid / country still needed on the current band and
/// mode?" with O(1) Set lookups per row.
struct WorkedIndex: Equatable {
    /// Every callsign in the logbook, any band/mode (uppercased).
    var callsigns: Set<String> = []
    /// "CALL|BAND|MODE"
    var callsignBandMode: Set<String> = []
    /// "GRID4|BAND|MODE"
    var gridBandMode: Set<String> = []
    /// "COUNTRY|BAND|MODE"
    var countryBandMode: Set<String> = []

    static func key(_ value: String, band: String, mode: String) -> String {
        "\(value)|\(band)|\(mode)"
    }

    static func build(from entries: [LogEntry]) -> WorkedIndex {
        var index = WorkedIndex()
        index.callsigns.reserveCapacity(entries.count)
        index.callsignBandMode.reserveCapacity(entries.count)

        for entry in entries {
            let call = entry.callsign.uppercased()
            guard !call.isEmpty else { continue }
            index.callsigns.insert(call)
            index.callsignBandMode.insert(key(call, band: entry.band, mode: entry.mode))

            let grid4 = String(entry.grid.prefix(4)).uppercased()
            if grid4.count == 4 {
                index.gridBandMode.insert(key(grid4, band: entry.band, mode: entry.mode))
            }

            // Older ADIF entries may predate the cached COUNTRY field.
            let country = entry.country
                ?? CountryResolver.countryAndCoordinates(for: entry.callsign).country
            if let country, !country.isEmpty {
                index.countryBandMode.insert(key(country, band: entry.band, mode: entry.mode))
            }
        }
        return index
    }
}

/// What a decoded station would still give us on the current band/mode.
struct NeededStatus: OptionSet, Hashable {
    let rawValue: UInt8

    static let callsign = NeededStatus(rawValue: 1 << 0)
    static let grid     = NeededStatus(rawValue: 1 << 1)
    static let dxcc     = NeededStatus(rawValue: 1 << 2)
}
