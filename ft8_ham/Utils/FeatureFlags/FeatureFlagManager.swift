//
//  FeatureFlagManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/02/26.
//

import Foundation
import Combine

@MainActor
final class FeatureFlagManager: ObservableObject {
    
    static let shared = FeatureFlagManager()
    
    private let provider: FeatureFlagProvider
    private let logger = AppLogger(category: "FFLAGS")
    private var refreshTimer: Timer?
    
    @Published private(set) var values: [FeatureFlag: Bool]

#if DEBUG
    // Key format matches the pre-existing "debug.newConfigViewOverride" key so UI tests
    // injecting that launch argument keep working unchanged.
    private static func overrideKey(for flag: FeatureFlag) -> String {
        "debug.\(flag.rawValue)Override"
    }

    // Computed so it correctly handles both Bool objects (set by setOverride) and
    // string values ("1"/"0") injected via XCUIApplication launchArguments.
    private func override(for flag: FeatureFlag) -> Bool? {
        let key = Self.overrideKey(for: flag)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }
#endif
    
    private init(provider: FeatureFlagProvider = RemoteConfigProvider()) {
        self.provider = provider
        self.values = Dictionary(
            uniqueKeysWithValues: FeatureFlag.allCases.map { ($0, $0.defaultValue) }
        )
        startAutoRefresh()
    }
    
    func isEnabled(_ flag: FeatureFlag) -> Bool {
#if DEBUG
        if let override = override(for: flag) { return override }
#endif
        return values[flag] ?? flag.defaultValue
    }
    
    private func startAutoRefresh() {
        refresh()
        
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    
    func refresh() {
        provider.refreshAllFlags { [weak self] in
            guard let self else { return }
            
            let oldValues = self.values
            var newValues: [FeatureFlag: Bool] = [:]
            for flag in FeatureFlag.allCases {
                newValues[flag] = self.provider.boolValue(for: flag)
            }
            
            Task { @MainActor in
                self.values = newValues
#if DEBUG
                // Re-apply any debug overrides on top of remote values
                for flag in FeatureFlag.allCases {
                    if let override = self.override(for: flag) {
                        self.values[flag] = override
                    }
                }
#endif
                self.logChanges(from: oldValues, to: newValues)
            }
        }
    }
    
    private func logChanges(from old: [FeatureFlag: Bool], to new: [FeatureFlag: Bool]) {
        for flag in FeatureFlag.allCases {
            let oldValue = old[flag] ?? flag.defaultValue
            let newValue = new[flag] ?? flag.defaultValue
            
            if oldValue != newValue {
                logger.info("Feature flag '\(flag.rawValue)' changed: \(oldValue) → \(newValue)")
            }
        }
    }

#if DEBUG
    func setOverride(_ flag: FeatureFlag, value: Bool) {
        values[flag] = value
        UserDefaults.standard.set(value, forKey: Self.overrideKey(for: flag))
        logger.info("[DEBUG] Feature flag '\(flag.rawValue)' overridden to: \(value)")
    }
#endif
}
