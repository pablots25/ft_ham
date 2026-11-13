//
//  MockAnalyticsLogger.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 13/11/26.
//

import Foundation
@testable import ft8_ham

/// Records analytics events instead of sending them to Firebase.
final class MockAnalyticsLogger: AnalyticsLogging {
    struct Event {
        let name: String
        let parameters: [String: Any]

        func string(_ key: String) -> String? { parameters[key] as? String }
        func int(_ key: String) -> Int? { (parameters[key] as? NSNumber)?.intValue }
    }

    private(set) var events: [Event] = []

    var lastEvent: Event? { events.last }

    func logEvent(_ name: String, parameters: [String: Any]?) {
        events.append(Event(name: name, parameters: parameters ?? [:]))
    }
}
