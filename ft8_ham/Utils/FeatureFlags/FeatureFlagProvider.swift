//
//  FeatureFlagProvider.swift
//  ft_ham
//
//  Created by Pablo Turrion on 05/02/26.
//


import Foundation

protocol FeatureFlagProvider {
    func boolValue(for flag: FeatureFlag) -> Bool
    func refreshAllFlags(completion: @escaping () -> Void)
}

