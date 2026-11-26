//
// VoiceLevelHistory.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Accelerate
import Foundation

/// Loudness of raw PCM for the live push-to-talk engine, which has no
/// built-in meter like `AVAudioRecorder`.
enum VoiceInputLevel {
    /// Target length of one waveform bar's worth of audio (25 bars/s).
    static let chunkDuration: Double = 0.04
    /// Reported for digital silence instead of -infinity.
    static let silenceDecibels: Float = -160

    /// dBFS of a root-mean-square amplitude.
    static func decibels(rms: Float) -> Float {
        guard rms.isFinite, rms > 0 else { return silenceDecibels }
        return max(silenceDecibels, 20 * log10f(rms))
    }

    /// Splits one tap buffer into equal chunks of about `chunkSize` frames
    /// and returns each chunk's loudness. Tap buffers rarely divide evenly,
    /// so the chunk count is rounded rather than carrying a remainder.
    static func chunkDecibels(_ samples: UnsafeBufferPointer<Float>, chunkSize: Int) -> [Float] {
        guard let base = samples.baseAddress, !samples.isEmpty else { return [] }
        let chunkCount = max(1, Int((Double(samples.count) / Double(max(1, chunkSize))).rounded()))
        let length = samples.count / chunkCount
        guard length > 0 else { return [] }
        return (0..<chunkCount).map { index in
            let start = index * length
            let count = index == chunkCount - 1 ? samples.count - start : length
            var rms: Float = 0
            vDSP_rmsqv(base + start, 1, &rms, vDSP_Length(count))
            return decibels(rms: rms)
        }
    }
}

/// Input levels behind the live waveform in the voice recording bar.
///
/// The capture backends report loudness in dBFS: the classic recorder once
/// per poll, the live push-to-talk engine in bursts as its tap buffers
/// arrive. Samples are queued and moved into the visible history one per
/// display tick, so the waveform grows at a steady pace either way. A
/// backlog past `maxBacklog` drains at once to keep the bars close to the
/// voice.
struct VoiceLevelHistory: Equatable {
    /// Anything quieter than this shows as a flat bar; room noise usually
    /// sits just below it.
    static let floorDecibels: Float = -50

    /// The most bars any recording bar can show; older levels scroll off.
    let capacity: Int
    let maxBacklog: Int
    /// Normalized 0...1 levels, oldest first.
    private(set) var levels: [Float] = []
    private var pending: [Float] = []

    init(capacity: Int = 300, maxBacklog: Int = 4) {
        self.capacity = max(1, capacity)
        self.maxBacklog = max(0, maxBacklog)
    }

    /// Maps dBFS onto 0...1, linear in decibels above `floorDecibels`.
    static func normalized(decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        let value = (decibels - floorDecibels) / -floorDecibels
        return min(1, max(0, value))
    }

    /// Queues raw dBFS samples from the capture backend.
    mutating func enqueue(decibels: [Float]) {
        pending.append(contentsOf: decibels.map(Self.normalized(decibels:)))
    }

    /// One display tick: shows the next queued level, plus any backlog
    /// beyond `maxBacklog`. Holds still when nothing is queued.
    mutating func tick() {
        guard !pending.isEmpty else { return }
        let count = max(1, pending.count - maxBacklog)
        append(contentsOf: pending.prefix(count))
        pending.removeFirst(count)
    }

    /// The most recent `count` levels, oldest first, for a bar that fits
    /// only that many.
    func recent(_ count: Int) -> ArraySlice<Float> {
        levels.suffix(max(0, count))
    }

    mutating func reset() {
        levels.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
    }

    private mutating func append<S: Sequence>(contentsOf newLevels: S) where S.Element == Float {
        levels.append(contentsOf: newLevels)
        if levels.count > capacity {
            levels.removeFirst(levels.count - capacity)
        }
    }
}

/// Publishes the level history to the waveform view alone, at display rate,
/// so the recording view model (observed by the whole chat screen) does not
/// republish 25 times a second.
@MainActor
final class VoiceLevelMeter: ObservableObject {
    @Published private(set) var history = VoiceLevelHistory()

    /// Feeds one poll's worth of samples and advances the display by a tick.
    func ingest(decibels: [Float]) {
        var next = history
        next.enqueue(decibels: decibels)
        next.tick()
        if next != history {
            history = next
        }
    }

    func reset() {
        guard history != VoiceLevelHistory(capacity: history.capacity, maxBacklog: history.maxBacklog) else { return }
        history.reset()
    }
}
