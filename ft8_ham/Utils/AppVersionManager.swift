//
//  AppVersionManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/02/26.
//

import Foundation

class AppVersionManager {
    static let shared = AppVersionManager()
    
    @AppStorage("lastSeenAppVersion") private var lastSeenAppVersion: String = ""
    @AppStorage("hasSeenWhatsNew") private var hasSeenWhatsNew: Bool = false
    
    private init() {}
    
    var currentVersion: String {
        Bundle.main.appVersion
    }
    
    var shouldShowWhatsNew: Bool {
        let currentVer = currentVersion
        let lastVer = lastSeenAppVersion
        
        // Show What's New if version has changed or user hasn't seen it yet
        return currentVer != lastVer || !hasSeenWhatsNew
    }
    
    func markWhatsNewAsViewed() {
        lastSeenAppVersion = currentVersion
        hasSeenWhatsNew = true
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version).\(build)"
    }
}
