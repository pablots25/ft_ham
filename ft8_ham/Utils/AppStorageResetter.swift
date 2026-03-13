//
//  AppStorageResetter.swift
//  ft_ham
//
//  Extracted from ConfigurationView.swift
//

import Foundation

enum AppStorageResetter {
    static let onboardingKey = "hasCompletedOnboarding"
    
    static let tutorialKeys = [
        "hasSeenFloatingButtonTutorial",
        "hasSeenSlideToReplyTutorial"
    ]
    
    static func resetTutorials() {
        for key in tutorialKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }
    
    static func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: onboardingKey)
        UserDefaults.standard.synchronize()
    }
}
