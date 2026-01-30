//
//  ft8_hamApp.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 18/10/25.
//

import SwiftUI
import FirebaseCore
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        FirebaseApp.configure()
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self // to handle notifications in foreground
        let logger = AppLogger(category: "APP")
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                logger.log(.error, "Error requesting notification permissions: \(error.localizedDescription)")
            } else if granted {
                logger.info("Notification permissions granted")
            } else {
                logger.info("Notification permissions denied")
            }
        }
        
        return true
    }
    
    // Show notifications even when the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}


@main
struct ft8_hamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject private var viewModel = FT8ViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .modifier(QSOLogConfirmationModifier(manager: viewModel))
                .inAppPrompts()
        }
        .onChange(of: scenePhase) { _, newPhase in
            AnalyticsManager.shared.flushAllOnBackground(scenePhase: newPhase)
        }
    }
}

