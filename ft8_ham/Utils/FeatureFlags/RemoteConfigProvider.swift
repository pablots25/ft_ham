//
//  RemoteConfigProvider.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 2/2/26.
//

import Foundation
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

// MARK: - RemoteConfigProvider

final class RemoteConfigProvider: FeatureFlagProvider {
    
    private let remoteConfig: RemoteConfig
    private var lastFetchDate: Date?
    private var cachedPromptConfig: PromptConfig?
    
    init() {
        remoteConfig = RemoteConfig.remoteConfig()
        
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
        // This ensures the app works even if Firebase Remote Config hasn't been fetched
        // See: firebase-prompt-config-default.json in project root
        let defaultJSON = defaultPromptConfigJSON()
        do {
            try remoteConfig.setDefaults(from: ["prompt_config": defaultJSON])
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
    
    private func shouldRefresh() -> Bool {
        guard let lastFetchDate else { return true }
        return Date().timeIntervalSince(lastFetchDate) > 30
    }
    
    func refreshAllFlags(completion: @escaping () -> Void) {
        guard shouldRefresh() else {
            completion()
            return
        }
        
        remoteConfig.fetchAndActivate { [weak self] _, _ in
            self?.lastFetchDate = Date()
            self?.cachedPromptConfig = nil  // Clear cache to fetch fresh config
            completion()
        }
    }
    
    func boolValue(for flag: FeatureFlag) -> Bool {
        remoteConfig[flag.rawValue].boolValue
    }

    // MARK: - Prompt Configuration Methods

    func intValue(for key: String, defaultValue: Int) -> Int {
        let value = remoteConfig[key].numberValue.intValue ?? defaultValue
        return value > 0 ? value : defaultValue
    }

    func boolValue(for key: String, defaultValue: Bool) -> Bool {
        let stringValue = remoteConfig[key].stringValue ?? ""
        return stringValue.lowercased() == "true" ? true : defaultValue
    }
    
    // MARK: - Prompt Config JSON
    
    func getPromptConfig() -> PromptConfig {
        if let cached = cachedPromptConfig {
            return cached
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
}
