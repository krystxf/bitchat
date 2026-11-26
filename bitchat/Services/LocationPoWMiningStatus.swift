//
// LocationPoWMiningStatus.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation

/// Location messages on their way out while they do their proof of work.
///
/// `ChatOutgoingCoordinator` puts a pending bubble in the chat as soon as a
/// location message is sent, then records it here under that bubble's
/// message ID: when mining began, how fast the progress should move, and
/// when the signed event went out. The bubble reads it to show progress, and
/// the coordinator reads it to decide whether the bubble gets a moment to
/// finish its progress before it is swapped for the sent message.
@MainActor
final class LocationPoWMiningStatus: ObservableObject {
    static let shared = LocationPoWMiningStatus()

    struct Send: Equatable {
        let startedAt: Date
        /// Seconds the progress paces itself against
        /// (`PoWSendProgress.pace(forTargetBits:)`).
        let pace: TimeInterval
        /// When the signed event went out; nil while mining.
        var finishedAt: Date?

        var isMining: Bool { finishedAt == nil }
    }

    /// Keyed by the pending bubble's message ID.
    @Published private(set) var sends: [String: Send] = [:]

    var isMining: Bool { sends.values.contains(where: \.isMining) }

    /// When the oldest message still mining began; nil when none is.
    var miningSince: Date? {
        sends.values.filter(\.isMining).map(\.startedAt).min()
    }

    func send(for messageID: String) -> Send? {
        sends[messageID]
    }

    func begin(messageID: String, targetBits: Int, now: Date = Date()) {
        sends[messageID] = Send(startedAt: now, pace: PoWSendProgress.pace(forTargetBits: targetBits))
    }

    /// The event is signed and sent: the progress can complete.
    func finish(messageID: String, now: Date = Date()) {
        guard var send = sends[messageID], send.isMining else { return }
        send.finishedAt = now
        sends[messageID] = send
    }

    /// The bubble was swapped for the sent message, or its send failed.
    func end(messageID: String) {
        sends.removeValue(forKey: messageID)
    }

    /// Whether the bubble showed its progress, so it should finish visibly
    /// before the swap. False for a send that never began or one that took
    /// less than `PoWSendProgress.revealDelay`, as at the default 8 bits.
    func showedProgress(for messageID: String, now: Date = Date()) -> Bool {
        guard let send = sends[messageID] else { return false }
        let end = send.finishedAt ?? now
        return end.timeIntervalSince(send.startedAt) >= PoWSendProgress.revealDelay
    }
}

/// Timing of a location message's sending progress.
enum PoWSendProgress {
    /// Nothing pending shows before this: at the default 8 bits mining
    /// takes about a millisecond, and a bubble that dims and lights up again
    /// within a frame reads as a flicker.
    static let revealDelay: TimeInterval = 0.5

    /// How long a bubble that showed its progress keeps it after the event
    /// went out, so the progress can fill and fade before the swap.
    static let finishDuration: TimeInterval = 0.6

    /// Seconds the progress paces itself against. Mining has no true
    /// percentage, so this is the expected mining time on an older phone,
    /// held to a third of the mining time cap so the progress is well along
    /// by the time the cap steps the target down. Never under half a
    /// second.
    static func pace(forTargetBits bits: Int) -> TimeInterval {
        let expected = NostrPoW.estimatedMiningTime(forTargetBits: bits)
        let cap = NostrPoW.miningTimeCap(forTargetBits: bits)
        return max(0.5, min(expected, cap / 3))
    }
}

extension BitchatMessage {
    /// A location message of mine that has not gone out: still mining its
    /// proof of work (`.sending`) or dropped (`.failed`). Public messages
    /// carry no other delivery status, so the status tells.
    var isUnsentLocationMessage: Bool {
        guard !isPrivate, senderPeerID?.isGeoChat == true else { return false }
        switch deliveryStatus {
        case .sending, .failed:
            return true
        default:
            return false
        }
    }
}
