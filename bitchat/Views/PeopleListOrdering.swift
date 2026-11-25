//
// PeopleListOrdering.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

/// Row ordering for the people sheet's rosters.
///
/// Rows stay where they are while the sheet is open: ids already on screen
/// keep their relative order (minus anyone who left) and newcomers append in
/// the producer's order. Without this, recency-sorted rosters reshuffle on
/// every heartbeat and rows move out from under a tap.
enum PeopleListOrdering {
    /// Linear in the roster size; duplicate ids in `current` collapse to
    /// their first occurrence so `ForEach` identities stay unique.
    static func stableOrder(previous: [String], current: [String]) -> [String] {
        let currentIDs = Set(current)
        var ordered: [String] = []
        ordered.reserveCapacity(current.count)
        var placed = Set<String>()
        placed.reserveCapacity(current.count)
        for id in previous where currentIDs.contains(id) && placed.insert(id).inserted {
            ordered.append(id)
        }
        for id in current where placed.insert(id).inserted {
            ordered.append(id)
        }
        return ordered
    }
}

/// Remembers the order a roster was last shown in, so a section keeps its
/// rows in place without lifecycle callbacks.
///
/// A `List` builds rows lazily, so `onAppear` on a section runs once per
/// row as rows scroll into view. It can't seed the order once, and
/// reseeding mid-scroll moved rows under the user's finger. Asking this
/// memory for the order on every render needs no callback: the result
/// depends only on the previous result and the current ids, so repeated
/// renders with the same ids return the same order.
@MainActor
final class PeopleListOrderMemory {
    private var shownIDs: [String] = []
    private var generation: Int?

    /// Returns `current` in stable order and remembers that order. A
    /// `generation` different from the last call's forgets the remembered
    /// order first, so the roster shows in the producer's order again.
    func order(_ current: [String], generation: Int = 0) -> [String] {
        if generation != self.generation {
            self.generation = generation
            shownIDs = []
        }
        shownIDs = PeopleListOrdering.stableOrder(previous: shownIDs, current: current)
        return shownIDs
    }
}
