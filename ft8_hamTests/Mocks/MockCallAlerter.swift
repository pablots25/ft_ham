import Foundation
@testable import ft8_ham

/// Records "calling you" and watched-station alerts instead of playing sounds, vibrating or
/// posting notifications.
@MainActor
final class MockCallAlerter: CallAlerting {
    struct Call {
        let kind: CallAlertKind
        let message: FT8Message
        let sound: Bool
        let haptic: Bool
        let notification: Bool
    }

    private(set) var calls: [Call] = []

    func alert(_ kind: CallAlertKind, for message: FT8Message, sound: Bool, haptic: Bool, notification: Bool) {
        calls.append(Call(kind: kind, message: message, sound: sound, haptic: haptic, notification: notification))
    }
}
