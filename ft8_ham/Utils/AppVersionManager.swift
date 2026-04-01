//
//  AppVersionManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/02/26.
//

import Foundation
import SwiftUI

class AppVersionManager {
    static let shared = AppVersionManager()
    
    @AppStorage("lastSeenAppVersion") private var lastSeenAppVersion: String = ""
    @AppStorage("hasSeenWhatsNew") private var hasSeenWhatsNew: Bool = false
    
    private let remoteConfig = RemoteConfigProvider()
    
    private init() {
        // Singleton initialization is intentionally empty.
    }
    
    var currentVersion: String {
        Bundle.main.appVersion
    }

    private var currentShortVersion: String {
        Bundle.main.shortVersion
    }
    
    var shouldShowWhatsNew: Bool {
        // Check if What's New is enabled in Firebase
        let whatsNewConfig = remoteConfig.getWhatsNewConfig()
        guard whatsNewConfig.whatsNew.enabled else {
            return false
        }
        
        let currentVer = currentShortVersion
        let lastVer = lastSeenAppVersion

        // Only show if version changed AND user had a previous version
        guard !lastVer.isEmpty else { return false }

        // Show only on major/minor bumps (ignore patch/build changes)
        if let currentMM = parseMajorMinor(from: currentVer),
           let lastMM = parseMajorMinor(from: lastVer) {
            if currentMM.major != lastMM.major { return true }
            return currentMM.minor > lastMM.minor
        }

        // Fallback to previous behavior if parsing fails
        return currentVer != lastVer
    }
    
    func markWhatsNewAsViewed() {
        lastSeenAppVersion = currentShortVersion
        hasSeenWhatsNew = true
    }

    private func parseMajorMinor(from version: String) -> (major: Int, minor: Int)? {
        let parts = version
            .split(whereSeparator: { $0 == "." || $0 == "-" })
            .compactMap { Int($0) }

        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version).\(build)"
    }

    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
