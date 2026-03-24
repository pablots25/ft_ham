//
//  RemoteConfigProvider.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 2/2/26.
//

import Foundation
import FirebaseCore
import FirebaseRemoteConfig

// MARK: - Prompt Configuration Models

struct PromptConfig: Decodable {
    let prompts: PromptsSettings
    
    struct PromptsSettings: Decodable {
        let rate: RatePromptSettings
        let share: SharePromptSettings
        let donation: DonationPromptSettings
        let common: CommonPromptSettings
    }
    
    struct RatePromptSettings: Decodable {
        let threshold: Int
        let enabled: Bool
    }
    
    struct SharePromptSettings: Decodable {
        let threshold: Int
        let enabled: Bool
    }
    
    struct DonationPromptSettings: Decodable {
        let qsoThreshold: Int
        let adifThreshold: Int
        let txThreshold: Int
        let enabled: Bool
    }
    
    struct CommonPromptSettings: Decodable {
        let probability: Int
        let reminderDelay: Int
        let donationProbability: Int
        let donationCooldown: Int
    }
    
    static func defaults() -> PromptConfig {
        PromptConfig(
            prompts: PromptConfig.PromptsSettings(
                rate: RatePromptSettings(threshold: 4, enabled: true),
                share: SharePromptSettings(threshold: 6, enabled: true),
                donation: DonationPromptSettings(qsoThreshold: 10, adifThreshold: 2, txThreshold: 20, enabled: true),
                common: CommonPromptSettings(probability: 25, reminderDelay: 10, donationProbability: 25, donationCooldown: 20)
            )
        )
    }
}

// MARK: - What's New Configuration Models

struct WhatsNewConfig: Decodable {
    let whatsNew: WhatsNewSettings
    
    struct WhatsNewSettings: Decodable {
        let enabled: Bool
        let features: [WhatsNewItem]
        let improvements: [WhatsNewItem]
        let bugFixes: [WhatsNewItem]
        
        struct WhatsNewItem: Decodable, Identifiable {
            let id: String
            let title: String
            let description: String
        }
    }
    
    static func defaults() -> WhatsNewConfig {
        WhatsNewConfig(
            whatsNew: WhatsNewSettings(
                enabled: false,
                features: [],
                improvements: [],
                bugFixes: []
            )
        )
    }
}

// MARK: - RemoteConfigProvider

final class RemoteConfigProvider: FeatureFlagProvider {

    private let remoteConfig: RemoteConfig?
    private var lastFetchDate: Date?
    private var cachedPromptConfig: PromptConfig?
    private var cachedWhatsNewConfig: WhatsNewConfig?

    init() {
        guard AppEnvironment.current.isProduction else {
            remoteConfig = nil
            return
        }

      guard FirebaseApp.app() != nil else {
        remoteConfig = nil
        return
      }

        let remoteConfig = RemoteConfig.remoteConfig()
        self.remoteConfig = remoteConfig

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0
        remoteConfig.configSettings = settings

        remoteConfig.setDefaults(
            Dictionary(
                uniqueKeysWithValues: FeatureFlag.allCases.map {
                    ($0.rawValue, $0.defaultValue as NSObject)
                }
            )
        )

        // Set default prompt config JSON
        let defaultPromptJSON = defaultPromptConfigJSON()
        let defaultWhatsNewJSON = defaultWhatsNewConfigJSON()
        do {
            try remoteConfig.setDefaults(from: [
                "prompt_config": defaultPromptJSON,
                "whats_new_config": defaultWhatsNewJSON
            ])
        } catch {
            print("Error setting Remote Config defaults: \(error)")
        }
    }
    
    private func defaultPromptConfigJSON() -> String {
        """
        {
          "prompts": {
            "rate": {
              "threshold": 4,
              "enabled": true
            },
            "share": {
              "threshold": 6,
              "enabled": true
            },
            "donation": {
              "qsoThreshold": 10,
              "adifThreshold": 2,
              "txThreshold": 20,
              "enabled": true
            },
            "common": {
              "probability": 25,
              "reminderDelay": 10,
              "donationProbability": 25,
              "donationCooldown": 20
            }
          }
        }
        """
    }
    
    private func defaultWhatsNewConfigJSON() -> String {
        """
        {
          "whatsNew": {
            "enabled": false,
            "features": [
              {
                "id": "contacts_management",
                "title": "🔗 Contacts Management",
                "description": "Improved contact handling and integration throughout the app."
              },
              {
                "id": "country_display",
                "title": "🌍 Country Display in Grid",
                "description": "See the country associated with each callsign directly in the grid view."
              },
              {
                "id": "callsign_location",
                "title": "📍 Callsign Location Detection",
                "description": "Automatic location inference based on callsign prefix."
              },
              {
                "id": "map_controls",
                "title": "🗺️ Map Controls",
                "description": "Customize which map elements are visible."
              }
            ],
            "improvements": [
              {
                "id": "autocq_behavior",
                "title": "🔊 AutoCQ Smart Behavior",
                "description": "AutoCQ won't call CQ if the DX is already in your QSO list."
              },
              {
                "id": "dynamic_logs",
                "title": "📅 Dynamic Log Files",
                "description": "Timestamped log files (FT_HAM_Log_YYYYMMDD_HHMMSS) prevent overwriting and organize logs automatically."
              },
              {
                "id": "better_export",
                "title": "📤 Better Log Export",
                "description": "• Export only recent logs\\n• Select specific date ranges\\n• Incremental export support"
              },
              {
                "id": "app_prompts",
                "title": "💬 App Prompts",
                "description": "Improved consistency and usability of in-app notifications."
              }
            ],
            "bugFixes": [
              {
                "id": "auto_tx_logging",
                "title": "⚡ Auto TX & Logging",
                "description": "Fixed interleaved QSO entries that were incorrectly marked as invalid when report exchanges weren't sequential."
              },
              {
                "id": "callsign_switching",
                "title": "📻 Callsign Switching",
                "description": "Fixed issue where the app could continue transmitting to the previous station instead of switching to the new target callsign."
              },
              {
                "id": "general_improvements",
                "title": "🔧 General Improvements",
                "description": "Various stability and performance enhancements."
              }
            ]
          }
        }
        """
    }
    
    private func shouldRefresh() -> Bool {
        guard let lastFetchDate else { return true }
        return Date().timeIntervalSince(lastFetchDate) > 3600
    }
    
    func refreshAllFlags(completion: @escaping () -> Void) {
      guard let remoteConfig else {
        completion()
        return
      }

        guard shouldRefresh() else {
            completion()
            return
        }
        
        let logger = AppLogger(category: "REMOTECONFIG")
        logger.debug("Starting Firebase Remote Config fetch - will update: prompt_config, whats_new_config, and feature flags")
        
        remoteConfig.fetchAndActivate { [weak self] status, error in
            guard let self else { return }
            
            self.lastFetchDate = Date()
            self.cachedPromptConfig = nil  // Clear cache to fetch fresh config
            self.cachedWhatsNewConfig = nil  // Clear cache to fetch fresh config
            
            if let error = error {
                logger.error("Firebase Remote Config fetch failed: \(error.localizedDescription)")
            } else {
                logger.debug("Firebase Remote Config fetch completed successfully")
                logger.debug("Status: \(status == .successFetchedFromRemote ? "Fetched from Remote" : "Fetched from Cache")")
                
                // Eagerly load both configs to ensure they're parsed correctly
                _ = self.getPromptConfig()
                _ = self.getWhatsNewConfig()
                logger.debug("Both prompt_config and whats_new_config loaded and validated")
            }
            
            completion()
        }
    }
    
    func boolValue(for flag: FeatureFlag) -> Bool {
      remoteConfig?[flag.rawValue].boolValue ?? flag.defaultValue
    }

    // MARK: - Prompt Configuration Methods

    func intValue(for key: String, defaultValue: Int) -> Int {
      let value = remoteConfig?[key].numberValue.intValue ?? defaultValue
        return value > 0 ? value : defaultValue
    }

    func boolValue(for key: String, defaultValue: Bool) -> Bool {
      let stringValue = remoteConfig?[key].stringValue ?? ""
        return stringValue.lowercased() == "true" ? true : defaultValue
    }
    
    // MARK: - Prompt Config JSON
    
    func getPromptConfig() -> PromptConfig {
        if let cached = cachedPromptConfig {
            return cached
        }

      guard let remoteConfig else {
        let config = PromptConfig.defaults()
        cachedPromptConfig = config
        return config
      }
        
        let jsonString = remoteConfig["prompt_config"].stringValue ?? defaultPromptConfigJSON()
        let decoder = JSONDecoder()
        
        do {
            let config = try decoder.decode(PromptConfig.self, from: jsonString.data(using: .utf8) ?? Data())
            self.cachedPromptConfig = config
            return config
        } catch {
            print("Error decoding prompt config: \(error)")
            return PromptConfig.defaults()
        }
    }
    
    // MARK: - What's New Config JSON
    
    func getWhatsNewConfig() -> WhatsNewConfig {
        if let cached = cachedWhatsNewConfig {
            return cached
        }

      guard let remoteConfig else {
        let config = WhatsNewConfig.defaults()
        cachedWhatsNewConfig = config
        return config
      }
        
        let jsonString = remoteConfig["whats_new_config"].stringValue ?? defaultWhatsNewConfigJSON()
        let decoder = JSONDecoder()
        
        do {
            let config = try decoder.decode(WhatsNewConfig.self, from: jsonString.data(using: .utf8) ?? Data())
            self.cachedWhatsNewConfig = config
            return config
        } catch {
            print("Error decoding whats new config: \(error)")
            return WhatsNewConfig.defaults()
        }
    }
    
    // MARK: - Config Summary (for debugging)
    
    func getConfigurationSummary() -> String {
        let promptConfig = getPromptConfig()
        let whatsNewConfig = getWhatsNewConfig()
        
        let promptsEnabled = [
            "rate: \(promptConfig.prompts.rate.enabled)",
            "share: \(promptConfig.prompts.share.enabled)",
            "donation: \(promptConfig.prompts.donation.enabled)"
        ].joined(separator: ", ")
        
        let whatsNewItems = whatsNewConfig.whatsNew.features.count + 
                           whatsNewConfig.whatsNew.improvements.count + 
                           whatsNewConfig.whatsNew.bugFixes.count
        
        return """
        📱 Firebase Remote Config Status:
        ✅ prompt_config: Loaded [\(promptsEnabled)]
        ✅ whats_new_config: Loaded [enabled: \(whatsNewConfig.whatsNew.enabled), items: \(whatsNewItems)]
        """
    }
}
