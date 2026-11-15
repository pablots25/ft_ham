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
    private(set) var userProperties: [String: String?] = [:]

    var lastEvent: Event? { events.last }

    func events(named name: String) -> [Event] {
        events.filter { $0.name == name }
    }

    func logEvent(_ name: String, parameters: [String: Any]?) {
        events.append(Event(name: name, parameters: parameters ?? [:]))
    }

    func setUserProperty(_ value: String?, forName name: String) {
        userProperties[name] = value
    }

    func reset() {
        events.removeAll()
        userProperties.removeAll()
    }
}
