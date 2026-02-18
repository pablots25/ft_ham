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
    
    private init() {}
    
    var currentVersion: String {
        Bundle.main.appVersion
    }
    
    var shouldShowWhatsNew: Bool {
        // Disabled: keep logic for easy re-enable.
        // let currentVer = currentVersion
        // let lastVer = lastSeenAppVersion
        //
        // Only show if version changed AND user had a previous version
        // return !lastVer.isEmpty && currentVer != lastVer
        false
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
