//
//  CountryResolver.swift
//  ft_ham
//
//  Created by Pablo Turrion on 8/1/26.
//

import Foundation

final class CountryResolver {
    private static let appLogger = AppLogger(category: "CNTY")
    
    // -----------------------------------------------------
    // MARK: - CTY plist Handling
    // -----------------------------------------------------
    struct CTYEntry: Codable {
        let country: String
        let prefix: String // This is the Primary/ADIF prefix, NOT the lookup key
        let exactCallsign: Bool?
        let latitude: Double?
        let longitude: Double?
        
        private enum CodingKeys: String, CodingKey {
            case country = "Country"
            case prefix = "Prefix"
            case exactCallsign = "ExactCallsign"
            case latitude = "Latitude"
            case longitude = "Longitude"
        }
    }
    
    // Loaded table maps specific Prefix Keys (e.g. "W1", "N8") to Entry Data
    private static let ctyTableFromFile: [String: CTYEntry]? = {
        guard let url = Bundle.main.url(forResource: "cty", withExtension: "plist") else {
            appLogger.error("CTY plist not found in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            // The plist is a Dictionary at the root: <dict> ... </dict>
            // We decode it directly into [String: CTYEntry]
            let table = try PropertyListDecoder().decode([String: CTYEntry].self, from: data)
            
            // Normalize keys to uppercase just in case — but only rebuild the
            // (~29k entry) dictionary if some key actually has lowercase ASCII.
            let needsNormalization = table.keys.contains { key in
                key.utf8.contains { $0 >= 0x61 && $0 <= 0x7A }
            }
            guard needsNormalization else {
                appLogger.debug("Loaded CTY table with \(table.count) entries")
                return table
            }
            var normalizedTable: [String: CTYEntry] = [:]
            normalizedTable.reserveCapacity(table.count)
            for (key, value) in table {
                normalizedTable[key.uppercased()] = value
            }
            
            appLogger.debug("Loaded CTY table with \(normalizedTable.count) entries")
            return normalizedTable
            
        } catch {
            appLogger.error("Failed to decode CTY plist: \(error)")
            return nil
        }
    }()
    
    // -----------------------------------------------------
    // MARK: - Lookup cache
    // -----------------------------------------------------
    // The same callsigns are resolved over and over (every decode of a station,
    // twice per logbook record...). Cache results; bound the size so a very long
    // session cannot grow it without limit.
    private static let cacheLock = NSLock()
    private static var cache: [String: CountryInfo] = [:]
    private static var reportedMisses: Set<String> = []
    private static let maxCacheEntries = 4096

    /// Warms the CTY table off the calling thread (e.g. at launch), so the first
    /// real lookup does not pay the plist decode on the main thread.
    static func preload() {
        DispatchQueue.global(qos: .utility).async {
            _ = ctyTableFromFile
        }
    }

    // -----------------------------------------------------
    // MARK: - Static Lookup Function
    // -----------------------------------------------------
/// Resolves the DXCC entity a callsign is operating from.
///
/// Compound callsigns are resolved from their modifier, not their base call:
/// "I/VE6XAD" is Italy and "W1AW/VE3" is Canada, while operating suffixes such
/// as "/P" or "/MM" and district digits such as "/1" leave the entity alone.
static func countryAndCoordinates(for callsign: String) -> CountryInfo {
    let upperCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    cacheLock.lock()
    if let cached = cache[upperCall] {
        cacheLock.unlock()
        return cached
    }
    cacheLock.unlock()

    let info = resolve(upperCall, original: callsign)

    cacheLock.lock()
    if cache.count >= maxCacheEntries { cache.removeAll(keepingCapacity: true) }
    cache[upperCall] = info
    cacheLock.unlock()
    return info
}

private static func resolve(_ upperCall: String, original callsign: String) -> CountryInfo {
    guard let table = ctyTableFromFile else {
        return CountryInfo(country: nil, coordinates: nil)
    }

    // A compound call is looked up through its modifier: "I/VE6XAD" is worked
    // as Italy, not Canada. Anything the parser does not recognize (a partially
    // decoded call, say) falls back to the raw text, unchanged from before.
    let lookupCall = CompoundCallsign.fromDecodedToken(upperCall)?.countryLookupToken ?? upperCall

    // Longest prefix matching algorithm
    // 1. Start with the full callsign (in case it's an ExactCallsign)
    var searchString = lookupCall
    
    // 2. Trim the callsign character by character from the end
    // Example: "EA1ABC" -> "EA1AB" -> "EA1A" -> "EA1" -> "EA" -> "E"
    while !searchString.isEmpty {
        if let entry = table[searchString] {
            // If the entry is marked as 'ExactCallsign', only accept it if the full callsign matches
            if entry.exactCallsign == true {
                if searchString == lookupCall {
                    return mapToCountryInfo(entry)
                }
                // Not a complete match, skip and keep searching
            } else {
                // Standard prefix (like EA, EA6, W6), return this match
                // By searching longest-to-shortest, we ensure EA6 matches before EA
                return mapToCountryInfo(entry)
            }
        }
        searchString.removeLast()
    }

    // Report each unknown prefix once per session: this used to log an error
    // (two regex sanitisations + a Crashlytics non-fatal in release) and a
    // Firebase event on every decode of every unresolved callsign.
    cacheLock.lock()
    let firstTime = reportedMisses.insert(upperCall).inserted
    cacheLock.unlock()
    if firstTime {
        appLogger.warning("Country not found for callsign: \(callsign)")
        AnalyticsManager.shared.logCountryNotFound(prefix: AnalyticsManager.callsignPrefix(callsign))
    }
    return CountryInfo(country: nil, coordinates: nil)
}

private static func mapToCountryInfo(_ entry: CTYEntry) -> CountryInfo {
    let coords = entry.latitude.flatMap { lat in 
        entry.longitude.map { Coordinates(lat: lat, lon: $0) } 
    }
    return CountryInfo(country: entry.country, coordinates: coords)
}
    
    private static func mapEntryToInfo(_ match: CTYEntry) -> CountryInfo {
        let coords = match.latitude.flatMap { lat in
            match.longitude.map { Coordinates(lat: lat, lon: $0) }
        }
        return CountryInfo(country: match.country, coordinates: coords)
    }
}
