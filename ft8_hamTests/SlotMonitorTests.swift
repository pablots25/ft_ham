//
//  SlotMonitorTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 17/9/26.
//

import XCTest
@testable import ft8_ham

/// The streaming spectrogram shared by the waterfall and the decoder.
/// Pure DSP, no audio hardware involved.
final class SlotMonitorTests: XCTestCase {

    private struct Row {
        let values: [UInt8]
        let firstBinHz: Float
        let binHz: Float
    }

    /// Collects every row the monitor emits.
    private func collectRows(_ monitor: FT8SlotMonitor) -> (() -> [Row]) {
        let lock = NSLock()
        var rows: [Row] = []
        monitor.rowHandler = { ptr, count, firstBinHz, binHz, _, _ in
            let values = Array(UnsafeBufferPointer(start: ptr, count: Int(count)))
            lock.lock(); rows.append(Row(values: values, firstBinHz: firstBinHz, binHz: binHz)); lock.unlock()
        }
        return { lock.lock(); defer { lock.unlock() }; return rows }
    }

    private func sine(hz: Double, seconds: Double, sampleRate: Double = 12_000, amplitude: Float = 0.5) -> [Float] {
        (0 ..< Int(seconds * sampleRate)).map { i in
            amplitude * Float(sin(2 * .pi * hz * Double(i) / sampleRate))
        }
    }

    // MARK: - Geometry

    func test_ft8Geometry_matchesTheDecoder() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        XCTAssertEqual(monitor.rowPeriod, 0.08, accuracy: 1e-6, "two rows per 160 ms symbol")
        XCTAssertEqual(monitor.minFrequency, 200, accuracy: 0.01)
        XCTAssertEqual(monitor.maxFrequency, 3000, accuracy: 3.2, "top bin sits on the 3 kHz edge")
    }

    func test_ft4Geometry() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: true)
        XCTAssertEqual(monitor.rowPeriod, 0.024, accuracy: 1e-6)
        // ft8_lib truncates 200 Hz to a whole FT4 bin (20.83 Hz): 187.5 Hz.
        XCTAssertEqual(monitor.minFrequency, 200, accuracy: 21)
    }

    // MARK: - Rows

    /// Audio is analysed one symbol at a time regardless of how it is chunked,
    /// and a tone shows up in the column that maps to its frequency.
    func test_rowsFollowSymbols_andPlaceATone() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        let rows = collectRows(monitor)

        // 1.0 s of a 1500 Hz tone fed in odd-sized chunks: 6 whole symbols.
        let audio = sine(hz: 1500, seconds: 1.0)
        var pos = 0
        for chunk in [557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 557, 303] {
            audio[pos ..< pos + chunk].withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
            pos += chunk
        }
        XCTAssertEqual(pos, audio.count)

        // 1 s = 6 symbols × 2 sub-rows. The second sub-row of each block is
        // held back until the next audio callback ≥ 70 ms later, so right
        // after a burst the last block's second row is still pending.
        XCTAssertEqual(rows().count, 6 * 2 - 1)
        usleep(100_000)
        let tail = sine(hz: 1500, seconds: 0.001)
        tail.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        let emitted = rows()
        XCTAssertEqual(emitted.count, 6 * 2, "the held row is released on the next callback")

        let last = emitted.last!
        XCTAssertEqual(last.firstBinHz, 200, accuracy: 0.01)
        XCTAssertEqual(last.binHz, 3.125, accuracy: 1e-4)
        XCTAssertEqual(last.values.count, 898)

        let peak = last.values.indices.max { last.values[$0] < last.values[$1] }!
        let peakHz = last.firstBinHz + Float(peak) * last.binHz
        XCTAssertEqual(peakHz, 1500, accuracy: 3.2, "the tone lands on its own bin")
        XCTAssertGreaterThan(Int(last.values[peak]) - Int(last.values[peak + 40]), 40,
                             "at least 20 dB above a bin 125 Hz away")
    }

    // MARK: - Slots

    func test_snapshotAndReset_startsANewSlot() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        let audio = sine(hz: 1000, seconds: 0.5)   // 3 symbols + 240 samples spare
        audio.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }

        let snapshot = monitor.snapshotAndReset()
        XCTAssertEqual(snapshot.duration, 3 * 0.16, accuracy: 1e-6)
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 3)
        XCTAssertEqual(snapshot.minBin, 32, "200 Hz / 6.25 Hz")
        XCTAssertEqual(snapshot.symbolPeriod, 0.16, accuracy: 1e-6)

        // The partial block was dropped with the reset, so nothing is
        // carried into the next slot.
        let rows = collectRows(monitor)
        let more = sine(hz: 1000, seconds: 0.16 - 0.001)
        more.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        XCTAssertTrue(rows().isEmpty, "just under one symbol since the reset")
        XCTAssertEqual(monitor.snapshotAndReset().duration, 0)
    }

    /// The sequencer snapshots from the main actor and can run late; the
    /// block that completes just after the 15 s boundary must not wipe the
    /// slot. ft8_lib's own store is exactly one slot, so the monitor keeps
    /// a second one of headroom.
    func test_lateSnapshot_stillHoldsTheWholeSlot() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        let audio = sine(hz: 1000, seconds: 16.0)   // 100 symbols > 93 per slot
        audio.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        let snapshot = monitor.snapshotAndReset()
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 100)
        XCTAssertEqual(snapshot.duration, 16.0, accuracy: 1e-4)
    }

    /// Without any reset the store eventually fills and ft8_lib would
    /// silently ignore further audio; the waterfall must keep moving.
    func test_keepsEmittingRowsWithoutResets() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        let rows = collectRows(monitor)
        let audio = sine(hz: 1000, seconds: 40.0)   // 250 symbols > 186 stored
        audio.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        XCTAssertEqual(rows().count, 250 * 2 - 1, "all but the one held row")
    }

    /// Rows never reorder: a held row goes out before the next block's rows,
    /// and before a slot reset.
    func test_heldRowKeepsItsOrder() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        let lock = NSLock()
        var peaks: [Int] = []
        monitor.rowHandler = { ptr, count, _, _, _, _ in
            let row = UnsafeBufferPointer(start: ptr, count: Int(count))
            let peak = row.indices.max { row[$0] < row[$1] }!
            lock.lock(); peaks.append(peak); lock.unlock()
        }
        // Two symbols of 1000 Hz then two of 2000 Hz: every low row must
        // come out before every high row. (The STFT window spans two
        // symbols, so the rows around the change still lean low.)
        let low = sine(hz: 1000, seconds: 0.32)
        let high = sine(hz: 2000, seconds: 0.32)
        low.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        high.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        _ = monitor.snapshotAndReset()   // releases the held row

        lock.lock(); let seen = peaks; lock.unlock()
        XCTAssertEqual(seen.count, 8)
        let lowBin = Int(((1000.0 - 200) / 3.125).rounded())
        let highBin = Int(((2000.0 - 200) / 3.125).rounded())
        XCTAssertEqual(seen.first ?? -1, lowBin, accuracy: 1)
        XCTAssertEqual(seen.last ?? -1, highBin, accuracy: 1)
        XCTAssertEqual(seen, seen.sorted(), "rows reordered: \(seen)")
        XCTAssertTrue(seen.allSatisfy { abs($0 - lowBin) <= 1 || abs($0 - highBin) <= 1 }, "\(seen)")
    }

    /// Rows say which slot they belong to and how far into it they are;
    /// snapshots carry the same sequence, so a decode can find its rows.
    func test_rowsCarrySlotSequenceAndIndex() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        let lock = NSLock()
        var tags: [(UInt, Int)] = []
        monitor.rowHandler = { _, _, _, _, seq, row in lock.lock(); tags.append((seq, Int(row))); lock.unlock() }

        let audio = sine(hz: 1000, seconds: 0.48)   // 3 symbols
        audio.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        let first = monitor.snapshotAndReset()      // releases the held row, then resets
        audio.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        let second = monitor.snapshotAndReset()

        lock.lock(); let seen = tags; lock.unlock()
        XCTAssertEqual(seen.map { $0.1 }, [0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5], "row index restarts with each slot")
        XCTAssertEqual(Set(seen.prefix(6).map { $0.0 }).count, 1)
        XCTAssertEqual(Set(seen.suffix(6).map { $0.0 }).count, 1)
        XCTAssertEqual(seen[0].0, UInt(first.slotSequence), "rows and the snapshot of a slot share its sequence")
        XCTAssertEqual(seen[6].0, UInt(second.slotSequence))
        XCTAssertEqual(second.slotSequence, first.slotSequence + 1)
    }

    func test_reconfigure_switchesProtocol() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        monitor.reconfigureIsFT4(true)
        XCTAssertTrue(monitor.isFT4)
        XCTAssertEqual(monitor.rowPeriod, 0.024, accuracy: 1e-6)
        let snapshot = monitor.snapshotAndReset()
        XCTAssertEqual(snapshot.symbolPeriod, 0.048, accuracy: 1e-6)
    }

    // MARK: - Shared decode path

    /// The whole point of sharing the monitor: a message streamed through it
    /// decodes from the snapshot exactly as it does from the batch path.
    func test_streamedSlot_decodes() {
        let engine = ft8_Engine()
        let message = "CQ EA4TST IN80"
        guard let audio = engine.generateFT8(message, frequency: 1400, isFT4: false, toFile: nil) else {
            return XCTFail("No audio generated")
        }
        let samples = audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        // Feed it the way the tap does: ~46 ms chunks.
        var pos = 0
        while pos < samples.count {
            let n = min(557, samples.count - pos)
            samples[pos ..< pos + n].withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
            pos += n
        }

        let snapshot = monitor.snapshotAndReset()
        XCTAssertGreaterThan(snapshot.duration, 12.0)

        let decoded = engine.decodeWaterfallSnapshot(snapshot, isFT4: false)
        let texts = decoded.compactMap { $0["text"] as? String }.map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(texts.contains(message), "'\(message)' decoded as \(texts)")

        let hit = decoded.first { ($0["text"] as? String)?.trimmingCharacters(in: .whitespaces) == message }
        XCTAssertEqual(hit?["frequency"] as? Double ?? 0, 1400, accuracy: 4)
    }

    /// An empty or very short slot reports "Partial slot" instead of nothing.
    func test_shortSnapshot_reportsPartialSlot() {
        let engine = ft8_Engine()
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        let audio = sine(hz: 1000, seconds: 1.0)
        audio.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        let decoded = engine.decodeWaterfallSnapshot(monitor.snapshotAndReset(), isFT4: false)
        XCTAssertEqual(decoded.compactMap { $0["text"] as? String }, ["Partial slot"])
    }
}
