//
//  RemoteConfigProvider.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 2/2/26.
//

import Foundation
import FirebaseRemoteConfig

final class RemoteConfigProvider: FeatureFlagProvider {
    
    private let remoteConfig: RemoteConfig
    private var lastFetchDate: Date?
    
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
            completion()
        }
    }
    
    func boolValue(for flag: FeatureFlag) -> Bool {
        remoteConfig[flag.rawValue].boolValue
    }
}
