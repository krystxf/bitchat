//
// BlockedAccounts.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Someone the user blocked, as the blocked accounts list shows them.
///
/// Mesh blocks are stored on the person's Noise fingerprint, location-channel
/// blocks on their Nostr public key; the list shows both so either can be
/// undone without typing a command.
struct BlockedAccount: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A mesh identity, by its Noise fingerprint.
        case mesh(fingerprint: String)
        /// A location-channel (Nostr) identity, by its lowercase hex key.
        case nostr(pubkeyHex: String)
    }

    let kind: Kind
    /// The name to show: the user's petname, the last name the person used,
    /// or a short form of their key when no name is known.
    let name: String

    var id: String {
        switch kind {
        case .mesh(let fingerprint): return "mesh:\(fingerprint)"
        case .nostr(let pubkeyHex): return "nostr:\(pubkeyHex)"
        }
    }

    /// The first characters of the fingerprint or key, to tell apart two
    /// accounts with the same name.
    var shortKey: String {
        switch kind {
        case .mesh(let fingerprint): return String(fingerprint.prefix(8))
        case .nostr(let pubkeyHex): return String(pubkeyHex.prefix(8))
        }
    }

    /// Sorted by name, then by key, so the list is stable.
    static func sorted(_ accounts: [BlockedAccount]) -> [BlockedAccount] {
        accounts.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
