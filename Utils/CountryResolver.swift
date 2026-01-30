//
//  CountryResolver.swift
//  ft8_ham
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
            
            // Normalize keys to uppercase just in case
            var normalizedTable: [String: CTYEntry] = [:]
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
    // MARK: - Static Lookup Function
    // -----------------------------------------------------
static func countryAndCoordinates(for callsign: String) -> CountryInfo {
    let upperCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    
    guard let table = ctyTableFromFile else {
        return CountryInfo(country: nil, coordinates: nil)
    }

    // --- ALGORITMO DE BÚSQUEDA POR PREFIJO MÁS LARGO ---
    
    // 1. Intentamos con el indicativo completo primero (por si es un ExactCallsign)
    var searchString = upperCall
    
    // 2. Vamos recortando el indicativo letra a letra desde el final
    // Ejemplo: "EA1ABC" -> "EA1AB" -> "EA1A" -> "EA1" -> "EA" -> "E"
    while !searchString.isEmpty {
        if let entry = table[searchString] {
            
            // Si la entrada marcada como 'ExactCallsign' es verdadera, 
            // solo la aceptamos si el indicativo coincide al 100%
            if entry.exactCallsign == true {
                if searchString == upperCall {
                    return mapToCountryInfo(entry)
                }
                // Si no es coincidencia exacta total, ignoramos esta entrada y seguimos buscando
            } else {
                // Es un prefijo normal (como EA, EA6, W6), devolvemos este
                // Al ir de más largo a más corto, garantizamos que EA6 gane a EA.
                return mapToCountryInfo(entry)
            }
        }
        searchString.removeLast()
    }

    appLogger.error("Country not found for callsign: \(callsign)")
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