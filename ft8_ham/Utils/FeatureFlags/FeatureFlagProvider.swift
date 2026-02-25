//
//  FeatureFlagProvider.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 2/2/26.
//


import Foundation

protocol FeatureFlagProvider {
    func boolValue(for flag: FeatureFlag) -> Bool
    func refreshAllFlags(completion: @escaping () -> Void)
}

