//
//  BandHopSchedulerStub.swift
//  ft_ham
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation
import Combine

/// No-op band-hop scheduler used when the premium package is not linked.
@MainActor
public final class BandHopSchedulerStub: BandHopSchedulerProtocol {
    public static let shared = BandHopSchedulerStub()

    private init() {}

    public var state: BandHopState { .stopped }

    public var statePublisher: AnyPublisher<BandHopState, Never> {
        Just(.stopped).eraseToAnyPublisher()
    }

    public var hopRequests: AnyPublisher<String, Never> {
        Empty().eraseToAnyPublisher()
    }

    public func start(schedule: BandHopSchedule, startingAt bandRaw: String?) {}
    public func stop() {}
    public func pause() {}
    public func resume() {}
    public func skipToNext() {}
}
