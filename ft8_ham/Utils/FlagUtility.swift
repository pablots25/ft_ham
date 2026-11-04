//
//  FlagUtility.swift
//  ft_ham
//
//  Created by Pablo Turrion on 12/2/26.
//

import Foundation

/// Utility to convert country names to flag emojis and add them to message text
final class FlagUtility {
    private static let appLogger = AppLogger(category: "FLAG")
    
    // MARK: - Country to Flag Emoji Mapping
    private static let countryToFlag: [String: String] = [
        // North America
        "United States": "🇺🇸",
        "Canada": "🇨🇦",
        "Mexico": "🇲🇽",
        
        // Europe - Western
        "Spain": "🇪🇸",
        "France": "🇫🇷",
        "Germany": "🇩🇪",
        "Italy": "🇮🇹",
        "United Kingdom": "🇬🇧",
        "England": "🏴󠁧󠁢󠁥󠁮󠁧󠁿",
        "Scotland": "🏴󠁧󠁢󠁳󠁣󠁴󠁿",
        "Wales": "🏴󠁧󠁢󠁷󠁬󠁳󠁿",
        "Northern Ireland": "🇬🇧",
        "Ireland": "🇮🇪",
        "Portugal": "🇵🇹",
        "Netherlands": "🇳🇱",
        "Belgium": "🇧🇪",
        "Luxembourg": "🇱🇺",
        "Switzerland": "🇨🇭",
        "Austria": "🇦🇹",
        
        // Europe - Northern
        "Norway": "🇳🇴",
        "Sweden": "🇸🇪",
        "Finland": "🇫🇮",
        "Denmark": "🇩🇰",
        "Iceland": "🇮🇸",
        
        // Europe - Eastern
        "Poland": "🇵🇱",
        "Czech Republic": "🇨🇿",
        "Slovakia": "🇸🇰",
        "Hungary": "🇭🇺",
        "Romania": "🇷🇴",
        "Bulgaria": "🇧🇬",
        "Ukraine": "🇺🇦",
        "Belarus": "🇧🇾",
        "Russia": "🇷🇺",
        "European Russia": "🇷🇺",
        "Asiatic Russia": "🇷🇺",
        "Kaliningrad": "🇷🇺",
        "Moldova": "🇲🇩",
        
        // Europe - Southern
        "Greece": "🇬🇷",
        "Croatia": "🇭🇷",
        "Serbia": "🇷🇸",
        "Bosnia-Herzegovina": "🇧🇦",
        "Montenegro": "🇲🇪",
        "North Macedonia": "🇲🇰",
        "Albania": "🇦🇱",
        "Slovenia": "🇸🇮",
        
        // Europe - Baltic
        "Estonia": "🇪🇪",
        "Latvia": "🇱🇻",
        "Lithuania": "🇱🇹",
        
        // Asia - East
        "Japan": "🇯🇵",
        "China": "🇨🇳",
        "South Korea": "🇰🇷",
        "North Korea": "🇰🇵",
        "Taiwan": "🇹🇼",
        "Hong Kong": "🇭🇰",
        "Macao": "🇲🇴",
        
        // Asia - Southeast
        "Thailand": "🇹🇭",
        "Vietnam": "🇻🇳",
        "Philippines": "🇵🇭",
        "Indonesia": "🇮🇩",
        "Malaysia": "🇲🇾",
        "Singapore": "🇸🇬",
        "Myanmar": "🇲🇲",
        "Cambodia": "🇰🇭",
        "Laos": "🇱🇦",
        "Brunei Darussalam": "🇧🇳",
        "Timor - Leste": "🇹🇱",
        
        // Asia - South
        "India": "🇮🇳",
        "Pakistan": "🇵🇰",
        "Bangladesh": "🇧🇩",
        "Sri Lanka": "🇱🇰",
        "Nepal": "🇳🇵",
        "Bhutan": "🇧🇹",
        "Maldives": "🇲🇻",
        
        // Asia - Central
        "Kazakhstan": "🇰🇿",
        "Uzbekistan": "🇺🇿",
        "Turkmenistan": "🇹🇲",
        "Kyrgyzstan": "🇰🇬",
        "Tajikistan": "🇹🇯",
        
        // Middle East
        "Turkey": "🇹🇷",
        "Israel": "🇮🇱",
        "Saudi Arabia": "🇸🇦",
        "United Arab Emirates": "🇦🇪",
        "Kuwait": "🇰🇼",
        "Qatar": "🇶🇦",
        "Bahrain": "🇧🇭",
        "Oman": "🇴🇲",
        "Yemen": "🇾🇪",
        "Jordan": "🇯🇴",
        "Lebanon": "🇱🇧",
        "Syria": "🇸🇾",
        "Iraq": "🇮🇶",
        "Iran": "🇮🇷",
        
        // Oceania
        "Australia": "🇦🇺",
        "New Zealand": "🇳🇿",
        "Papua New Guinea": "🇵🇬",
        "Fiji": "🇫🇯",
        "New Caledonia": "🇳🇨",
        "Solomon Islands": "🇸🇧",
        "Vanuatu": "🇻🇺",
        "Samoa": "🇼🇸",
        "American Samoa": "🇦🇸",
        "Guam": "🇬🇺",
        "Northern Mariana Islands": "🇲🇵",
        "Palau": "🇵🇼",
        "Micronesia": "🇫🇲",
        "Marshall Islands": "🇲🇭",
        "Kiribati": "🇰🇮",
        "Tuvalu": "🇹🇻",
        "Nauru": "🇳🇷",
        "Tonga": "🇹🇴",
        "Cook Islands": "🇨🇰",
        "French Polynesia": "🇵🇫",
        
        // Africa - North
        "Morocco": "🇲🇦",
        "Algeria": "🇩🇿",
        "Tunisia": "🇹🇳",
        "Libya": "🇱🇾",
        "Egypt": "🇪🇬",
        
        // Africa - West
        "Nigeria": "🇳🇬",
        "Ghana": "🇬🇭",
        "Senegal": "🇸🇳",
        "Ivory Coast": "🇨🇮",
        "Mali": "🇲🇱",
        "Burkina Faso": "🇧🇫",
        "Niger": "🇳🇪",
        "Guinea": "🇬🇳",
        "Benin": "🇧🇯",
        "Togo": "🇹🇬",
        "Sierra Leone": "🇸🇱",
        "Liberia": "🇱🇷",
        "Mauritania": "🇲🇷",
        "Gambia": "🇬🇲",
        "Guinea-Bissau": "🇬🇼",
        "Cape Verde": "🇨🇻",
        
        // Africa - East
        "Kenya": "🇰🇪",
        "Tanzania": "🇹🇿",
        "Uganda": "🇺🇬",
        "Ethiopia": "🇪🇹",
        "Somalia": "🇸🇴",
        "Djibouti": "🇩🇯",
        "Eritrea": "🇪🇷",
        "Rwanda": "🇷🇼",
        "Burundi": "🇧🇮",
        "South Sudan": "🇸🇸",
        
        // Africa - Southern
        "South Africa": "🇿🇦",
        "Zimbabwe": "🇿🇼",
        "Zambia": "🇿🇲",
        "Mozambique": "🇲🇿",
        "Botswana": "🇧🇼",
        "Eswatini": "🇸🇿",
        "Namibia": "🇳🇦",
        "Angola": "🇦🇴",
        "Malawi": "🇲🇼",
        "Madagascar": "🇲🇬",
        "Mauritius": "🇲🇺",
        "Reunion Island": "🇷🇪",
        "Seychelles": "🇸🇨",
        "Comoros": "🇰🇲",
        "Mayotte": "🇾🇹",
        
        // Africa - Central
        "Democratic Republic of the Congo": "🇨🇩",
        "Congo": "🇨🇬",
        "Cameroon": "🇨🇲",
        "Central African Republic": "🇨🇫",
        "Chad": "🇹🇩",
        "Gabon": "🇬🇦",
        "Equatorial Guinea": "🇬🇶",
        "Sao Tome & Principe": "🇸🇹",
        
        // South America
        "Brazil": "🇧🇷",
        "Argentina": "🇦🇷",
        "Chile": "🇨🇱",
        "Colombia": "🇨🇴",
        "Peru": "🇵🇪",
        "Venezuela": "🇻🇪",
        "Ecuador": "🇪🇨",
        "Bolivia": "🇧🇴",
        "Paraguay": "🇵🇾",
        "Uruguay": "🇺🇾",
        "Guyana": "🇬🇾",
        "Suriname": "🇸🇷",
        "French Guiana": "🇬🇫",
        
        // Central America & Caribbean
        "Guatemala": "🇬🇹",
        "Honduras": "🇭🇳",
        "El Salvador": "🇸🇻",
        "Nicaragua": "🇳🇮",
        "Costa Rica": "🇨🇷",
        "Panama": "🇵🇦",
        "Belize": "🇧🇿",
        "Cuba": "🇨🇺",
        "Jamaica": "🇯🇲",
        "Haiti": "🇭🇹",
        "Dominican Republic": "🇩🇴",
        "Puerto Rico": "🇵🇷",
        "Trinidad & Tobago": "🇹🇹",
        "Bahamas": "🇧🇸",
        "Barbados": "🇧🇧",
        "Saint Lucia": "🇱🇨",
        "Grenada": "🇬🇩",
        "Saint Vincent & Grenadines": "🇻🇨",
        "Antigua & Barbuda": "🇦🇬",
        "Dominica": "🇩🇲",
        "Saint Kitts & Nevis": "🇰🇳",
        "Aruba": "🇦🇼",
        "Curacao": "🇨🇼",
        "Bonaire": "🇧🇶",
        "Sint Maarten": "🇸🇽",
        "Martinique": "🇲🇶",
        "Guadeloupe": "🇬🇵",
        "Cayman Islands": "🇰🇾",
        "Turks & Caicos Islands": "🇹🇨",
        "British Virgin Islands": "🇻🇬",
        "US Virgin Islands": "🇻🇮",
        "Anguilla": "🇦🇮",
        "Montserrat": "🇲🇸",
        
        // Atlantic Islands
        "Canary Islands": "🇮🇨",
        "Madeira Islands": "🇵🇹",
        "Azores": "🇵🇹",
        "Greenland": "🇬🇱",
        "Faroe Islands": "🇫🇴",
        "Jan Mayen": "🇳🇴",
        "Svalbard": "🇳🇴",
        "Bermuda": "🇧🇲",
        "Saint Helena": "🇸🇭",
        "Ascension Island": "🇦🇨",
        "Tristan da Cunha": "🇹🇦",
        "Falkland Islands": "🇫🇰",
        "South Georgia Island": "🇬🇸",
        "Bouvet": "🇧🇻",
        
        // Pacific Islands
        "Hawaii": "🇺🇸",
        "Alaska": "🇺🇸",
        "Easter Island": "🇨🇱",
        "Galapagos Islands": "🇪🇨",
        
        // Antarctica
        "Antarctica": "🇦🇶",
        
        // Other Territories
        "Kosovo": "🇽🇰",
        "Palestine": "🇵🇸",
        "Gibraltar": "🇬🇮",
        "Isle of Man": "🇮🇲",
        "Jersey": "🇯🇪",
        "Guernsey": "🇬🇬",
        "Monaco": "🇲🇨",
        "Vatican City": "🇻🇦",
        "San Marino": "🇸🇲",
        "Liechtenstein": "🇱🇮",
        "Andorra": "🇦🇩",
        "Malta": "🇲🇹",
        "Cyprus": "🇨🇾",
        "Aland Islands": "🇦🇽",
        "Ceuta & Melilla": "🇪🇦",
        "Heard Island": "🇭🇲",
    ]
    
    // MARK: - CTY Country Name Aliases
    /// Maps CTY country names to the canonical names in countryToFlag.
    /// This handles cases where CTY and the flag map use different official names.
    private static let ctyAliases: [String: String] = [
        // CTY uses formal/historical names that differ from our canonical flag map keys
        "Republic of Korea": "South Korea",
        "DPR of Korea": "North Korea",
        "Cote d'Ivoire": "Ivory Coast",
        "Czech": "Czech Republic",
        "Russian Federation": "Russia",
        "Fed. Rep. of Germany": "Germany",
        "Dem. Rep. of the Congo": "Democratic Republic of the Congo",
        "Kingdom of Eswatini": "Eswatini",
        "Republic of South Sudan": "South Sudan",
        // Island territories — map to the sovereign state
        "Rodriguez Island": "Mauritius",
        "Agalega & St. Brandon": "Mauritius",
        "Annobon Island": "Equatorial Guinea",
        "Conway Reef": "Fiji",
        "Rotuma Island": "Fiji",
        "San Felix & San Ambrosio": "Chile",
        "Peter 1 Island": "Norway",
    ]
    
    /// Get flag emoji for a country name
    /// Handles CTY country name aliases to ensure proper flag resolution
    static func flag(for country: String?) -> String? {
        guard let country = country else { return nil }
        
        // Try exact match first
        if let flag = countryToFlag[country] {
            return flag
        }
        
        // Try alias mapping for known CTY variants
        if let canonicalName = ctyAliases[country],
           let flag = countryToFlag[canonicalName] {
            return flag
        }
        
        return nil
    }
    
    /// Add flag emojis to message text based on callsigns in the message
    /// - Parameters:
    ///   - message: The FT8Message to process
    /// - Returns: Message text with flag emojis added after callsigns
    static func addFlags(to message: FT8Message) -> String {
        var text = message.text
        
        // Get flags for sender and receiver
        let senderFlag = flag(for: message.senderCountry.country)
        let dxFlag = flag(for: message.dxCountry.country)
        
        // Add flag after sender callsign if available
        if let senderCallsign = message.callsign,
           !senderCallsign.isEmpty,
           let flag = senderFlag {
            // Find and replace the sender callsign with callsign + flag
            text = text.replacingOccurrences(
                of: senderCallsign,
                with: "\(senderCallsign) \(flag)",
                options: .caseInsensitive,
                range: text.startIndex..<text.endIndex
            )
        }
        
        // Add flag after DX callsign if available
        if let dxCallsign = message.dxCallsign,
           !dxCallsign.isEmpty,
           let flag = dxFlag,
           dxCallsign != message.callsign { // Avoid adding flag twice for same callsign
            // Find and replace the DX callsign with callsign + flag
            text = text.replacingOccurrences(
                of: dxCallsign,
                with: "\(dxCallsign) \(flag)",
                options: .caseInsensitive,
                range: text.startIndex..<text.endIndex
            )
        }
        
        return text
    }
}
