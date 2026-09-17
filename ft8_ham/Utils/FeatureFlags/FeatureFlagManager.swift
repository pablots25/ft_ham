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
        // Debug builds are driven by the Debug settings screen: the switch
        // the developer set, else the compiled-in DEBUG default. Remote Config
        // never flips a flag underneath them.
        return override(for: flag) ?? flag.defaultValue
#else
        return values[flag] ?? flag.defaultValue
#endif
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
#if DEBUG
            // The fetch still runs (prompt_config and whats_new_config come
            // from it), but remote flag values are not applied: see isEnabled.
            _ = self
#else
            guard let self else { return }
            let oldValues = self.values
            var newValues: [FeatureFlag: Bool] = [:]
            for flag in FeatureFlag.allCases {
                newValues[flag] = self.provider.boolValue(for: flag)
            }
            
            Task { @MainActor in
                // Assign once, and only when something actually changed: this
                // object is observed near the root of the view tree, so an
                // unconditional write every 30 s would invalidate most of the app.
                if self.values != newValues {
                    self.values = newValues
                }
                self.logChanges(from: oldValues, to: newValues)
            }
#endif
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
        // `values` is only mirrored here so the @Published change re-renders
        // observers; `isEnabled` reads the override itself.
        values[flag] = value
        UserDefaults.standard.set(value, forKey: Self.overrideKey(for: flag))
        logger.info("[DEBUG] Feature flag '\(flag.rawValue)' overridden to: \(value)")
    }

    /// Drops every override so each flag falls back to its DEBUG default.
    func resetOverrides() {
        for flag in FeatureFlag.allCases {
            UserDefaults.standard.removeObject(forKey: Self.overrideKey(for: flag))
            values[flag] = flag.defaultValue
        }
        logger.info("[DEBUG] Feature flag overrides reset to defaults")
    }
#endif
}
