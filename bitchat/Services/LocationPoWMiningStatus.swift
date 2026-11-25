//
// LocationPoWMiningStatus.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Which location-channel messages are still doing their proof of work, for
/// the "mining…" strip above the composer (`LocationPoWMiningBar`).
///
/// `ChatOutgoingCoordinator` begins an entry when a geohash send starts
/// (including one waiting for an earlier send to finish) and ends it once the
/// signed event exists. At the default 8 bits that is about a millisecond, so
/// the strip only shows itself when mining runs long enough to notice.
@MainActor
final class LocationPoWMiningStatus: ObservableObject {
    static let shared = LocationPoWMiningStatus()

    /// When the oldest message still mining started; nil when none is.
    @Published private(set) var miningSince: Date?

    /// Pending sends in the order they began.
    private var pending: [(id: UUID, startedAt: Date)] = []

    var isMining: Bool { miningSince != nil }

    /// Records a send that is about to mine. Pass the returned ID to
    /// `endMining(_:)` once its event is signed, whether mining succeeded or not.
    func beginMining(now: Date = Date()) -> UUID {
        let id = UUID()
        pending.append((id, now))
        publish()
        return id
    }

    func endMining(_ id: UUID) {
        pending.removeAll { $0.id == id }
        publish()
    }

    private func publish() {
        let oldest = pending.first?.startedAt
        if miningSince != oldest {
            miningSince = oldest
        }
    }
}
