//
//  TestDefaults.swift
//  ft8_hamTests
//
//  UserDefaults helpers for hosted unit tests.
//
//  A simulator can hold app settings outside the app container, for example
//  after `xcrun simctl spawn <device> defaults write pts.ft8-ham …`. That file
//  sits below the app's own domain, so `removeObject(forKey:)` does not make a
//  key absent: the read falls through to the outside value. Tests that need a
//  neutral value should write it explicitly. Tests that check behaviour when a
//  key is truly absent call `removeOrSkip(_:)`.
//

import XCTest

enum TestDefaults {

    /// Removes `keys` from the app domain and skips the test if any of them is
    /// still readable, which means another defaults domain on this simulator
    /// supplies it and the "key absent" case cannot be tested here.
    static func removeOrSkip(_ keys: String..., defaults: UserDefaults = .standard) throws {
        keys.forEach { defaults.removeObject(forKey: $0) }
        let shadowed = keys.compactMap { key in
            defaults.object(forKey: key).map { "\(key) = \($0)" }
        }
        guard shadowed.isEmpty else {
            throw XCTSkip(
                "This simulator has app settings outside the app container (\(shadowed.joined(separator: ", "))). " +
                "Erase the simulator or delete data/Library/Preferences/pts.ft8-ham.plist in its device folder."
            )
        }
    }
}
