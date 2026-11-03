//
//  WSPRCaptureBuffer.swift
//  ft_ham
//

import Foundation

/// Raw audio of the WSPR slot in progress.
///
/// FT8/FT4 are decoded from the spectrogram `FT8SlotMonitor` builds as
/// audio arrives. WSPR is decoded by the Rust library from the samples
/// themselves, so while WSPR is selected the audio tap also copies every
/// buffer here. Inactive, `append` is a no-op.
///
/// Thread-safe: `append` runs on the monitor queue, the rest on the main actor.
final class WSPRCaptureBuffer: @unchecked Sendable {

    /// Rate of the audio handed to `append` (the audio manager's output rate).
    let sampleRate: Double
    /// Samples kept per slot; anything past it is dropped so sample 0 stays
    /// on the slot start.
    let capacity: Int

    private let lock = NSLock()
    private var samples: [Float] = []
    private var active = false
    /// Seconds between the slot start and the moment the buffer was last
    /// reset at a boundary. nil until the first boundary (capture started
    /// mid-slot, so it is not aligned).
    private var startOffset: TimeInterval?

    /// Longest start offset that is still padded. A larger one means the
    /// boundary was missed (suspension), so the capture is not slot-aligned.
    static let maxAlignmentOffset: TimeInterval = 5

    init(sampleRate: Double, maxDuration: TimeInterval) {
        self.sampleRate = sampleRate
        self.capacity = Int(maxDuration * sampleRate)
    }

    var isActive: Bool {
        lock.withLock { active }
    }

    /// Starts capturing from scratch. The first slot is not aligned.
    func start() {
        lock.withLock {
            active = true
            samples.removeAll(keepingCapacity: true)
            startOffset = nil
        }
    }

    /// Stops capturing and frees the audio.
    func stop() {
        lock.withLock {
            active = false
            samples = []
            startOffset = nil
        }
    }

    func append(_ chunk: [Float]) {
        lock.withLock {
            guard active else { return }
            let room = capacity - samples.count
            guard room > 0 else { return }
            samples.append(contentsOf: chunk.prefix(room))
        }
    }

    /// Hands over the slot captured so far and starts the next one.
    ///
    /// The buffer is reset slightly after the boundary (the sequencer wakes
    /// late), so the audio of that gap went to the previous slot. The decoder
    /// measures DT from sample 0, so the returned samples are padded with
    /// that much silence at the front.
    /// - Parameters:
    ///   - nextSlotStart: start of the slot that begins now.
    ///   - now: current corrected time.
    /// - Returns: the finished slot's audio, slot-aligned when possible.
    func harvest(nextSlotStart: Date, now: Date) -> [Float] {
        lock.withLock {
            var captured = samples
            if let offset = startOffset, offset > 0, offset < Self.maxAlignmentOffset {
                let pad = Int(offset * sampleRate)
                captured = [Float](repeating: 0, count: pad) + captured
            }
            samples.removeAll(keepingCapacity: true)
            startOffset = now.timeIntervalSince(nextSlotStart)
            return captured
        }
    }

    /// Drops the slot in progress (e.g. after a band hop). The next slot is
    /// not aligned until the following boundary.
    func discardCurrentSlot() {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            startOffset = nil
        }
    }

    /// Float32 samples as `Data`, the layout `decodeAudioBuffer` expects.
    static func data(from samples: [Float]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
