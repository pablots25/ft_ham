//
//  SeededRandomNumberGenerator.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import Foundation

/// Deterministic xorshift64* generator for tests that need repeatable
/// "random" choices.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}
