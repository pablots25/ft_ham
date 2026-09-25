//
//  TabRouter.swift
//  ft_ham
//
//  Created by Pablo Turrion on 25/09/26.
//

import Combine
import Foundation

/// The root tabs, with the tags `ContentView` gives them.
enum AppTab: Int {
    case transmissions = 0
    case waterfall = 1
    case map = 2
    case logbook = 3
    case configuration = 4
}

/// Carries a tab switch requested from outside the view tree, such as a
/// notification action. The request stays pending until `ContentView` reads
/// it, so it also works when the action launches the app.
@MainActor
final class TabRouter: ObservableObject {
    static let shared = TabRouter()

    @Published private(set) var pendingTab: AppTab?

    func open(_ tab: AppTab) {
        pendingTab = tab
    }

    /// Returns the pending tab once and clears it.
    func consume() -> AppTab? {
        defer { pendingTab = nil }
        return pendingTab
    }
}
