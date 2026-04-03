//
//  AppStorageResetter.swift
//  ft_ham
//
//  Created by Pablo Turrion on 13/03/26.
//

import Foundation

enum AppStorageResetter {
    static let onboardingKey = "hasCompletedOnboarding"
    
    static let tutorialKeys = [
        "hasSeenFloatingButtonTutorial",
        "hasSeenSlideToReplyTutorial",
        "hasSeenMessageColumnTutorial"
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
