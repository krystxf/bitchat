//
// ReactionIntakeGate.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Spam filtering for incoming public reaction lines (`MessageReaction`).
///
/// Reactions skip the ordinary public-message limits (`MessageRateLimiter`
/// and the pipeline's content dedup). Those limits fit chat text: five
/// messages per sender in a burst, and the same text from anyone at most a
/// few times. Reactions are cheap and alike by design: a lively chat
/// reacts often, and many people send the very same line (👍 to one
/// message). So a reaction never spends a sender's message budget.
///
/// Instead each sender gets a bucket of their own: `capacity` reactions in
/// a burst, refilled at `refillPerSecond` (about 60 a minute), so one peer
/// still cannot flood. A line that repeats the sender's last reaction on
/// the same message and emoji changes nothing; the gate drops it as a
/// no-op, and it costs the sender nothing.
struct ReactionIntakeGate {
    enum Verdict: Equatable {
        /// A new reaction or a change: let it through.
        case accept
        /// The same state again: nothing to do, and no strike.
        case duplicate
        /// Over the sender's reaction budget.
        case rateLimited
    }

    static let defaultCapacity: Double = 30
    static let defaultRefillPerSecond: Double = 1

    private struct Bucket {
        var tokens: Double
        var lastRefill: Date
    }

    /// The last reaction state a sender set on one message and emoji.
    private struct LastState {
        let removes: Bool
        let timestamp: Date
    }

    let capacity: Double
    let refillPerSecond: Double
    private let maxSenders: Int
    private let maxRememberedStates: Int

    private var buckets: [String: Bucket] = [:]
    private var lastStates: [String: LastState] = [:]
    /// Insertion order of `lastStates`, oldest first, for eviction.
    private var stateOrder: [String] = []

    init(
        capacity: Double = Self.defaultCapacity,
        refillPerSecond: Double = Self.defaultRefillPerSecond,
        maxSenders: Int = TransportConfig.uiSenderRateBucketMaxEntries,
        maxRememberedStates: Int = 4_096
    ) {
        self.capacity = max(1, capacity)
        self.refillPerSecond = refillPerSecond
        self.maxSenders = max(1, maxSenders)
        self.maxRememberedStates = max(1, maxRememberedStates)
    }

    /// Decides on a reaction line from `senderKey`, sent at `timestamp`.
    mutating func admit(
        _ event: MessageReaction.Event,
        senderKey: String,
        timestamp: Date,
        now: Date = Date()
    ) -> Verdict {
        let stateKey = "\(senderKey)|\(event.targetID)|\(event.emoji)"
        let last = lastStates[stateKey]
        // Repeating the latest state is a no-op. An older line that arrives
        // late (history sync) is no repeat: it goes to the timeline, which
        // orders reactions by time.
        if let last, last.removes == event.removes, timestamp >= last.timestamp {
            return .duplicate
        }
        guard spendToken(for: senderKey, now: now) else { return .rateLimited }
        if timestamp >= (last?.timestamp ?? .distantPast) {
            remember(LastState(removes: event.removes, timestamp: timestamp), for: stateKey)
        }
        return .accept
    }

    /// Forgets every sender and state (the message wipes).
    mutating func reset() {
        buckets.removeAll()
        lastStates.removeAll()
        stateOrder.removeAll()
    }

    // MARK: Private

    private mutating func spendToken(for senderKey: String, now: Date) -> Bool {
        var bucket = buckets[senderKey] ?? {
            evictSenderIfNeeded()
            return Bucket(tokens: capacity, lastRefill: now)
        }()
        let elapsed = now.timeIntervalSince(bucket.lastRefill)
        if elapsed > 0 {
            bucket.tokens = min(capacity, bucket.tokens + elapsed * refillPerSecond)
            bucket.lastRefill = now
        }
        guard bucket.tokens >= 1 else {
            buckets[senderKey] = bucket
            return false
        }
        bucket.tokens -= 1
        buckets[senderKey] = bucket
        return true
    }

    private mutating func evictSenderIfNeeded() {
        guard buckets.count >= maxSenders,
              let oldest = buckets.min(by: { $0.value.lastRefill < $1.value.lastRefill })?.key else { return }
        buckets.removeValue(forKey: oldest)
    }

    private mutating func remember(_ state: LastState, for key: String) {
        if lastStates.updateValue(state, forKey: key) == nil {
            stateOrder.append(key)
        }
        guard stateOrder.count > maxRememberedStates else { return }
        let overflow = stateOrder.count - maxRememberedStates
        for key in stateOrder.prefix(overflow) {
            lastStates.removeValue(forKey: key)
        }
        stateOrder.removeFirst(overflow)
    }
}
