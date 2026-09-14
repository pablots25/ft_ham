//
//  BandHopProtocol.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import Combine

// MARK: - Schedule (pure data, shared with the premium package as JSON)

/// One stop in the band-hopping rotation.
public struct BandHopStep: Codable, Hashable, Identifiable {
    public var id: UUID
    /// `FT8Message.Band.rawValue`, e.g. "20m".
    public var bandRaw: String
    public var dwellMinutes: Int

    public init(id: UUID = UUID(), bandRaw: String, dwellMinutes: Int) {
        self.id = id
        self.bandRaw = bandRaw
        self.dwellMinutes = max(1, dwellMinutes)
    }
}

/// The ordered list of bands to rotate through.
///
/// Persisted as JSON under `storageKey`; the premium settings view writes the
/// same shape, so both sides must keep the field names in sync.
public struct BandHopSchedule: Codable, Equatable {
    public static let storageKey = "bandHopSchedule"

    public var steps: [BandHopStep]

    public init(steps: [BandHopStep] = []) {
        self.steps = steps
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// Index of the step after `index`, wrapping around; nil when empty.
    public func nextIndex(after index: Int) -> Int? {
        guard !steps.isEmpty else { return nil }
        return (index + 1) % steps.count
    }

    public func index(ofBand bandRaw: String) -> Int? {
        steps.firstIndex { $0.bandRaw == bandRaw }
    }

    public static func load(from defaults: UserDefaults = .standard) -> BandHopSchedule {
        guard let data = defaults.data(forKey: storageKey),
              let schedule = try? JSONDecoder().decode(BandHopSchedule.self, from: data) else {
            return BandHopSchedule()
        }
        return schedule
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Scheduler state

public enum BandHopState: Equatable {
    case stopped
    /// Sitting on `bandRaw` until `until`, then hopping to the next step.
    case dwelling(bandRaw: String, until: Date)
    /// Countdown frozen (QSO in progress); `remaining` seconds left.
    case paused(bandRaw: String, remaining: TimeInterval)

    public var currentBandRaw: String? {
        switch self {
        case .stopped: return nil
        case .dwelling(let band, _), .paused(let band, _): return band
        }
    }
}

// MARK: - Protocol

/// Runs the dwell timer and asks the app to change band when it expires.
/// The scheduler never touches the radio itself: the app applies the hop
/// through its normal band-change path (which already drives CAT).
@MainActor
public protocol BandHopSchedulerProtocol: AnyObject {
    var state: BandHopState { get }
    var statePublisher: AnyPublisher<BandHopState, Never> { get }
    /// Emits the `bandRaw` to switch to whenever a dwell expires.
    var hopRequests: AnyPublisher<String, Never> { get }

    func start(schedule: BandHopSchedule, startingAt bandRaw: String?)
    func stop()
    func pause()
    func resume()
    func skipToNext()
}
