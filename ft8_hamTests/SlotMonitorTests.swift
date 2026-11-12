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

    // MARK: - Cutting at the UTC boundary

    /// A UTC FT8 slot index around late 2026 and its start time.
    private let slot: Int64 = 119_623_765
    private var slotStart: TimeInterval { Double(slot) * 15 }

    /// Feeds `samples` the way the tap does (~46 ms chunks), each chunk
    /// arriving at the time its last sample was captured, the first sample
    /// being captured at `start`.
    private func feedTimed(_ monitor: FT8SlotMonitor, _ samples: [Float], from start: TimeInterval) {
        var pos = 0
        while pos < samples.count {
            let n = min(557, samples.count - pos)
            let arrival = start + Double(pos + n) / 12_000
            samples[pos ..< pos + n].withUnsafeBufferPointer {
                monitor.feedSamples($0.baseAddress!, count: UInt($0.count), arrivalTime: arrival)
            }
            pos += n
        }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * 12_000))
    }

    /// The background case behind the "Severe system lag" reports: the
    /// sequencer collects slot N four seconds late. It still gets slot N cut
    /// at the boundary, and those four seconds stay with slot N+1.
    func test_lateCollection_getsTheSlotCutAtItsBoundary() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)            // sequencer starts slot N
        feedTimed(monitor, sine(hz: 1000, seconds: 19.0), from: slotStart)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot, "the monitor cut slot N itself")
        // Block k starts at 0.16 k s; the first starting past 15 s minus half a block is k = 94.
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 94)

        let next = monitor.snapshotAndReset()
        XCTAssertEqual(next.slotIndex, -1)
        XCTAssertEqual(next.waterfall.pointee.num_blocks, 118 - 94, "slot N+1 keeps the audio since the boundary")
        XCTAssertEqual(next.slotSequence, snapshot.slotSequence + 1)
    }

    /// On time, nothing changes: the audio of the boundary has not arrived
    /// yet, so the slot is cut on request as before.
    func test_onTimeCollection_cutsOnRequest() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 14.9), from: slotStart)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, -1, "cut on request")
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 93)

        // The last 100 ms of slot N arrive after the cut. They go to slot N+1
        // and must not make the monitor cut it again right away.
        feedTimed(monitor, sine(hz: 1000, seconds: 14.9), from: slotStart + 14.9)
        let next = monitor.snapshotAndReset(forSlot: slot + 1)
        XCTAssertEqual(next.slotIndex, -1, "slot N+1 was not cut early")
        XCTAssertEqual(next.waterfall.pointee.num_blocks, 93)
    }

    /// More than a whole slot late: the newest finished slot is returned and
    /// says which one it is, so its decodes get the right time and parity.
    func test_collectionSeveralSlotsLate_returnsTheNewestSlot() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 34.0), from: slotStart)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot + 1)
        XCTAssertEqual(snapshot.duration, 15.0, accuracy: 0.2)
    }

    /// FT4 slots are 7.5 s.
    func test_ft4_cutsAtTheHalfSlotBoundary() {
        let ft4Slot: Int64 = 239_247_530
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: true)
        _ = monitor.snapshotAndReset(forSlot: ft4Slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 10.0), from: Double(ft4Slot) * 7.5)

        let snapshot = monitor.snapshotAndReset(forSlot: ft4Slot)
        XCTAssertEqual(snapshot.slotIndex, ft4Slot)
        XCTAssertEqual(snapshot.duration, 7.5, accuracy: 0.05)
    }

    /// Audio fed without a time never cuts on its own: it is cut on request,
    /// as before.
    func test_untimedFeed_isOnlyCutOnRequest() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        let audio = sine(hz: 1000, seconds: 19.0)
        audio.withUnsafeBufferPointer { monitor.feedSamples($0.baseAddress!, count: UInt($0.count)) }
        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, -1)
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 118)
    }

    /// Audio lost on the way (interruption, route change) moves the clock
    /// forward: the boundary is still found on the real time.
    func test_lostAudio_resyncsTheClock() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 4.8), from: slotStart)
        // 3 s of audio never arrive: the next sample is captured at 7.8 s.
        feedTimed(monitor, sine(hz: 1000, seconds: 12.0), from: slotStart + 7.8)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot)
        XCTAssertEqual(snapshot.duration, 4.8 + 7.2, accuracy: 0.33, "cut at 15 s real time, not 15 s of audio")
    }

    /// A buffer that arrives late on its way to the monitor does not move
    /// the boundary: the earliest arrival is the one trusted.
    func test_lateArrivalJitter_doesNotMoveTheBoundary() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        let audio = sine(hz: 1000, seconds: 19.0)
        var pos = 0
        var chunk = 0
        while pos < audio.count {
            let n = min(557, audio.count - pos)
            // Every third buffer is held up 150 ms on the queue.
            let delay = chunk % 3 == 0 ? 0.150 : 0
            let arrival = slotStart + Double(pos + n) / 12_000 + delay
            audio[pos ..< pos + n].withUnsafeBufferPointer {
                monitor.feedSamples($0.baseAddress!, count: UInt($0.count), arrivalTime: arrival)
            }
            pos += n
            chunk += 1
        }
        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot)
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 94)
    }

    /// A slot cut at the boundary belongs to the band and protocol it was
    /// heard on: clearing the slot (band hop) or switching protocol drops it.
    func test_resetAndReconfigure_dropTheCutSlot() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 16.0), from: slotStart)
        monitor.resetSlot()
        XCTAssertEqual(monitor.snapshotAndReset(forSlot: slot).slotIndex, -1)

        _ = monitor.snapshotAndReset(forSlot: slot)
        feedTimed(monitor, sine(hz: 1000, seconds: 16.0), from: slotStart + 15)
        monitor.reconfigureIsFT4(true)
        monitor.reconfigureIsFT4(false)
        XCTAssertEqual(monitor.snapshotAndReset(forSlot: slot + 1).slotIndex, -1)
    }

    /// The common on-time case where the boundary audio wins the race: the
    /// sequencer wakes a few hundred ms after the boundary and the monitor
    /// has already cut. The sequencer gets that slot, and the blocks analysed
    /// since the boundary stay with slot N+1 (no reset, nothing dropped).
    func test_slightlyLateCollection_keepsTheBlocksSinceTheBoundary() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 15.5), from: slotStart)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot)
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 94)

        // Up to 30.5 s, so the audio of the next boundary has arrived too.
        feedTimed(monitor, sine(hz: 1000, seconds: 15.0), from: slotStart + 15.5)
        let next = monitor.snapshotAndReset(forSlot: slot + 1)
        XCTAssertEqual(next.slotIndex, slot + 1, "slot N+1 was cut at its own boundary too")
        XCTAssertEqual(next.slotSequence, snapshot.slotSequence + 1)
        XCTAssertEqual(next.duration, 15.0, accuracy: 0.2)
    }

    /// A slot cut but never collected (the sequencer skipped it, e.g. TX)
    /// must not be handed out for a later slot: the later request gets the
    /// audio of the slot it asked for.
    func test_staleCutSlot_isNotReturnedForALaterSlot() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        // Slot N, then 14.9 s of slot N+1. Slot N is cut but nobody takes it.
        feedTimed(monitor, sine(hz: 1000, seconds: 29.9), from: slotStart)

        let snapshot = monitor.snapshotAndReset(forSlot: slot + 1)
        XCTAssertEqual(snapshot.slotIndex, -1, "slot N+1 cut on request, not the stale slot N")
        XCTAssertEqual(snapshot.duration, 14.9, accuracy: 0.2)

        // And it is gone for good: the next request is a normal one too.
        feedTimed(monitor, sine(hz: 1000, seconds: 14.9), from: slotStart + 30)
        XCTAssertEqual(monitor.snapshotAndReset(forSlot: slot + 2).slotIndex, -1)
    }

    /// A cut slot is handed out once. A second request for the same slot
    /// gets the slot in progress, cut on request.
    func test_cutSlot_isHandedOutOnce() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 17.0), from: slotStart)

        XCTAssertEqual(monitor.snapshotAndReset(forSlot: slot).slotIndex, slot)
        let again = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(again.slotIndex, -1)
        XCTAssertEqual(again.duration, 2.0, accuracy: 0.2, "the 2 s of slot N+1 so far")
    }

    /// The sequencer starts mid-slot: the first slot is partial and is cut
    /// at its boundary like any other.
    func test_startMidSlot_firstSlotIsPartial() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        monitor.resetSlot()
        feedTimed(monitor, sine(hz: 1000, seconds: 6.0), from: slotStart + 10)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot)
        XCTAssertEqual(snapshot.duration, 5.0, accuracy: 0.2)
    }

    /// The app clock is corrected backwards mid-slot (SNTP sync). Times go
    /// back, so the monitor does not cut before the stamped boundary.
    func test_clockStepBackwards_neverCutsEarly() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 10.0), from: slotStart)
        // The clock steps back 2 s: the audio of 10..15 s is stamped 8..13 s.
        feedTimed(monitor, sine(hz: 1000, seconds: 5.0), from: slotStart + 8)
        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, -1, "no cut before the stamped boundary")
        XCTAssertEqual(snapshot.duration, 15.0, accuracy: 0.2, "no audio lost either")
    }

    /// The app clock is corrected forwards by more than a slot (first SNTP
    /// sync on a device far off). The slot in progress is cut as soon as the
    /// time moves on, and the sequencer still gets it.
    func test_clockStepForwards_cutsTheSlotInProgress() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 5.0), from: slotStart)
        // Stamped 20 s ahead from here on: now 25 s into the run, slot N+1.
        feedTimed(monitor, sine(hz: 1000, seconds: 3.0), from: slotStart + 25)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot)
        XCTAssertEqual(snapshot.duration, 5.0, accuracy: 0.2)
    }

    /// The sound card runs 0.1 % fast or slow against the wall clock (far
    /// worse than real hardware). Over ten slots every cut lands on the
    /// right slot and within 0.3 s of 15 s.
    func test_sampleClockDrift_keepsEveryCutNearItsBoundary() {
        for drift in [1.001, 0.999] {
            let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
            _ = monitor.snapshotAndReset(forSlot: slot - 1)
            let realRate = 12_000.0 * drift
            let audio = sine(hz: 1000, seconds: 15.4)
            var captured = 0
            for k in 0 ..< 10 {
                var pos = 0
                while pos < audio.count {
                    let n = min(557, audio.count - pos)
                    let arrival = slotStart + Double(captured + pos + n) / realRate
                    audio[pos ..< pos + n].withUnsafeBufferPointer {
                        monitor.feedSamples($0.baseAddress!, count: UInt($0.count), arrivalTime: arrival)
                    }
                    pos += n
                }
                captured += audio.count
                let wallNow = slotStart + Double(captured) / realRate
                let expected = Int64(floor(wallNow / 15)) - 1
                let snapshot = monitor.snapshotAndReset(forSlot: expected)
                XCTAssertEqual(snapshot.slotIndex, expected, "drift \(drift), slot \(k)")
                XCTAssertEqual(snapshot.duration, 15.0, accuracy: 0.3, "drift \(drift), slot \(k)")
            }
        }
    }

    /// The tap and the sequencer run on different threads. Hammer both at
    /// once: no crash, and no block is ever handed out twice.
    func test_concurrentFeedAndCollect_neverDuplicatesABlock() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        let audio = sine(hz: 1000, seconds: 60.0)
        let start = slotStart
        let doneLock = NSLock()
        var feedDone = false
        let isDone = { doneLock.lock(); defer { doneLock.unlock() }; return feedDone }

        DispatchQueue.global(qos: .userInitiated).async {
            var pos = 0
            while pos < audio.count {
                let n = min(557, audio.count - pos)
                let arrival = start + Double(pos + n) / 12_000
                audio[pos ..< pos + n].withUnsafeBufferPointer {
                    monitor.feedSamples($0.baseAddress!, count: UInt($0.count), arrivalTime: arrival)
                }
                pos += n
            }
            doneLock.lock(); feedDone = true; doneLock.unlock()
        }
        var collectedBlocks = 0
        var lastSequence: UInt = 0
        var requested = slot
        var finished = false
        let deadline = Date().addingTimeInterval(30)
        while !finished && Date() < deadline {
            let snapshot = monitor.snapshotAndReset(forSlot: requested)
            collectedBlocks += Int(snapshot.waterfall.pointee.num_blocks)
            XCTAssertGreaterThan(UInt(snapshot.slotSequence), lastSequence)
            lastSequence = UInt(snapshot.slotSequence)
            if snapshot.slotIndex >= 0 { requested = snapshot.slotIndex + 1 }
            finished = isDone()
            usleep(1_000)
        }
        XCTAssertTrue(finished, "the feed thread finished")
        collectedBlocks += Int(monitor.snapshotAndReset().waterfall.pointee.num_blocks)
        XCTAssertLessThanOrEqual(collectedBlocks, 375, "60 s is 375 blocks")
    }

    // MARK: - Kill switch (rxSlotCutOnAudioTime)

    /// Switched off, timed audio is treated exactly like untimed audio: the
    /// slot is only cut on request, as in 1.3.1.
    func test_cutsAtSlotBoundaryOff_onlyCutsOnRequest() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        XCTAssertTrue(monitor.cutsAtSlotBoundary, "on unless the app turns it off")
        monitor.cutsAtSlotBoundary = false
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 19.0), from: slotStart)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, -1)
        XCTAssertEqual(snapshot.waterfall.pointee.num_blocks, 118, "the same as untimed audio")
    }

    /// Switched off mid-run: from the next buffer on no slot is cut, and a
    /// slot already cut before that is still handed out (it holds real audio).
    func test_cutsAtSlotBoundary_switchedOffMidRun() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 16.0), from: slotStart)
        monitor.cutsAtSlotBoundary = false
        feedTimed(monitor, sine(hz: 1000, seconds: 16.0), from: slotStart + 16)

        XCTAssertEqual(monitor.snapshotAndReset(forSlot: slot).slotIndex, slot, "cut while it was on")
        feedTimed(monitor, sine(hz: 1000, seconds: 16.0), from: slotStart + 32)
        XCTAssertEqual(monitor.snapshotAndReset(forSlot: slot + 2).slotIndex, -1, "no cut once off")
    }

    /// Switched on mid-run: the monitor picks the clock up again and cuts at
    /// the next boundary.
    func test_cutsAtSlotBoundary_switchedOnMidRun() {
        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        monitor.cutsAtSlotBoundary = false
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, sine(hz: 1000, seconds: 10.0), from: slotStart)
        monitor.cutsAtSlotBoundary = true
        feedTimed(monitor, sine(hz: 1000, seconds: 7.0), from: slotStart + 10)

        let snapshot = monitor.snapshotAndReset(forSlot: slot)
        XCTAssertEqual(snapshot.slotIndex, slot)
        XCTAssertEqual(snapshot.duration, 15.0, accuracy: 0.2)
    }

    /// End to end: a message in slot N+1, collected 4 s late, still decodes,
    /// with a DT near its real start. Cut on request at that point, the slot
    /// would start 4 s into the message and the decoder would not find it.
    func test_lateCollection_stillDecodesTheNextSlot() {
        let engine = ft8_Engine()
        let message = "CQ EA4TST IN80"
        guard let audio = engine.generateFT8(message, frequency: 1400, isFT4: false, toFile: nil) else {
            return XCTFail("No audio generated")
        }
        let tx = audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var slotN1 = tx
        slotN1 += silence(seconds: 15.0 - Double(tx.count) / 12_000)

        let monitor = FT8SlotMonitor(sampleRate: 12_000, isFT4: false)
        _ = monitor.snapshotAndReset(forSlot: slot - 1)
        feedTimed(monitor, silence(seconds: 15.0), from: slotStart)
        // Late for slot N: by now 4 s of slot N+1 have been analysed.
        feedTimed(monitor, Array(slotN1.prefix(4 * 12_000)), from: slotStart + 15)
        XCTAssertEqual(monitor.snapshotAndReset(forSlot: slot).slotIndex, slot)
        // The rest of slot N+1 and 4 s of slot N+2, then late again.
        feedTimed(monitor, Array(slotN1.dropFirst(4 * 12_000)) + silence(seconds: 4.0), from: slotStart + 19)

        let snapshot = monitor.snapshotAndReset(forSlot: slot + 1)
        XCTAssertEqual(snapshot.slotIndex, slot + 1)
        let decoded = engine.decodeWaterfallSnapshot(snapshot, isFT4: false)
        let hit = decoded.first { ($0["text"] as? String)?.trimmingCharacters(in: .whitespaces) == message }
        XCTAssertNotNil(hit, "decoded as \(decoded.compactMap { $0["text"] as? String })")
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
