//
// ReactionOrphanStore.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation

/// Reaction lines (`MessageReaction`) whose target message is not in their
/// conversation yet. They wait here, out of the timeline, until the target
/// arrives (history sync, Nostr backfill, a late mesh relay). Then
/// `ConversationStore` moves them into the timeline beside it.
///
/// The store is bounded: each conversation keeps its newest
/// `capacityPerConversation` lines, all conversations together keep
/// `totalCapacity`, and a line leaves after `maxAge`. So reactions to
/// messages that never arrive cannot pile up.
struct ReactionOrphanStore {
    static let defaultCapacityPerConversation = 200
    static let defaultTotalCapacity = 2_000
    /// Long enough for a mesh history sync or a Nostr backfill to bring the
    /// target, short enough that the store empties itself.
    static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    private struct Entry {
        let message: BitchatMessage
        let targetID: String
        /// Arrival time. Age counts from here, not from the message's own
        /// timestamp: a reaction that comes with old history may still
        /// meet its target in the same sync.
        let heldAt: Date
    }

    let capacityPerConversation: Int
    let totalCapacity: Int
    let maxAge: TimeInterval

    /// Per conversation, oldest arrival first.
    private var entries: [ConversationID: [Entry]] = [:]
    private(set) var count = 0

    init(
        capacityPerConversation: Int = Self.defaultCapacityPerConversation,
        totalCapacity: Int = Self.defaultTotalCapacity,
        maxAge: TimeInterval = Self.defaultMaxAge
    ) {
        self.capacityPerConversation = max(1, capacityPerConversation)
        self.totalCapacity = max(1, totalCapacity)
        self.maxAge = maxAge
    }

    /// Holds a reaction line until `targetID` arrives in `conversationID`.
    /// Returns `false` when a line with the same message ID already waits
    /// there.
    @discardableResult
    mutating func hold(_ message: BitchatMessage, targetID: String, in conversationID: ConversationID, now: Date) -> Bool {
        removeExpired(now: now)
        var waiting = entries[conversationID, default: []]
        guard !waiting.contains(where: { $0.message.id == message.id }) else { return false }
        waiting.append(Entry(message: message, targetID: targetID, heldAt: now))
        count += 1
        if waiting.count > capacityPerConversation {
            waiting.removeFirst(waiting.count - capacityPerConversation)
            count -= 1
        }
        entries[conversationID] = waiting
        while count > totalCapacity {
            dropOldest()
        }
        return true
    }

    /// Removes and returns the lines waiting for `targetID` in
    /// `conversationID`, in arrival order.
    mutating func release(targetID: String, in conversationID: ConversationID, now: Date) -> [BitchatMessage] {
        removeExpired(now: now)
        guard let waiting = entries[conversationID],
              waiting.contains(where: { $0.targetID == targetID }) else { return [] }
        return release(in: conversationID, where: { $0 == targetID })
    }

    /// Removes and returns the lines in `conversationID` whose target
    /// `isPresent` reports, in arrival order.
    mutating func release(in conversationID: ConversationID, where isPresent: (String) -> Bool, now: Date) -> [BitchatMessage] {
        removeExpired(now: now)
        return release(in: conversationID, where: isPresent)
    }

    /// Moves every waiting line of `source` to `destination` (the store's
    /// conversation migration).
    mutating func move(from source: ConversationID, to destination: ConversationID) {
        guard source != destination, let moving = entries.removeValue(forKey: source) else { return }
        var merged = entries[destination, default: []]
        for entry in moving where !merged.contains(where: { $0.message.id == entry.message.id }) {
            merged.append(entry)
        }
        let duplicates = entries[destination, default: []].count + moving.count - merged.count
        count -= duplicates
        merged.sort { $0.heldAt < $1.heldAt }
        if merged.count > capacityPerConversation {
            count -= merged.count - capacityPerConversation
            merged.removeFirst(merged.count - capacityPerConversation)
        }
        entries[destination] = merged
    }

    /// Drops every line waiting in `conversationID`.
    mutating func discard(_ conversationID: ConversationID) {
        count -= entries.removeValue(forKey: conversationID)?.count ?? 0
    }

    /// Drops every waiting line (the message wipes).
    mutating func removeAll() {
        entries.removeAll()
        count = 0
    }

    func count(in conversationID: ConversationID) -> Int {
        entries[conversationID]?.count ?? 0
    }

    // MARK: Private

    private mutating func release(in conversationID: ConversationID, where isPresent: (String) -> Bool) -> [BitchatMessage] {
        guard let waiting = entries[conversationID] else { return [] }
        var released: [BitchatMessage] = []
        var kept: [Entry] = []
        for entry in waiting {
            if isPresent(entry.targetID) {
                released.append(entry.message)
            } else {
                kept.append(entry)
            }
        }
        guard !released.isEmpty else { return [] }
        count -= released.count
        entries[conversationID] = kept.isEmpty ? nil : kept
        return released
    }

    private mutating func removeExpired(now: Date) {
        guard count > 0 else { return }
        for (conversationID, waiting) in entries {
            let fresh = waiting.filter { now.timeIntervalSince($0.heldAt) < maxAge }
            guard fresh.count != waiting.count else { continue }
            count -= waiting.count - fresh.count
            entries[conversationID] = fresh.isEmpty ? nil : fresh
        }
    }

    private mutating func dropOldest() {
        guard let (conversationID, waiting) = entries.min(by: { lhs, rhs in
            (lhs.value.first?.heldAt ?? .distantFuture) < (rhs.value.first?.heldAt ?? .distantFuture)
        }), !waiting.isEmpty else {
            count = 0
            return
        }
        let rest = Array(waiting.dropFirst())
        entries[conversationID] = rest.isEmpty ? nil : rest
        count -= 1
    }
}
