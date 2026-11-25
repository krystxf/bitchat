//
// LocationProofOfWorkSettings.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// User preference for NIP-13 proof of work on location-channel messages
/// (Nostr kind 20000), the counterpart of the Android app's "proof of work"
/// setting.
///
/// With it on, every outgoing location message mines a nonce tag first (see
/// `NostrPoW`). That costs one person a moment and costs a spammer real time
/// for every message, and receivers that score it (this app's
/// `MessageRateLimiter`) let mined messages past the per-sender rate limit.
///
/// Defaults to on at 8 bits, which is what every send did before this
/// setting existed: about 256 hashes, a millisecond on any supported device,
/// and exactly `NostrPoW.rateLimitBypassBits`, so the default already earns
/// the relaxed limits. Android ships the option off (at 12 bits once on);
/// turning it off here would only make this app's messages easier to rate
/// limit, with nothing gained.
///
/// Off means no mining at all: the message is signed and sent immediately,
/// with no nonce tag.
enum LocationProofOfWorkSettings {
    private static let enabledKey = "locationPoW.enabled"
    private static let difficultyBitsKey = "locationPoW.difficultyBits"

    static let defaultDifficultyBits = NostrPoW.targetBits

    /// The difficulties the settings picker offers, in leading zero bits.
    /// Each step is 16 times the work of the one before. They are Android's
    /// named levels from "very low" to "very high"; its 0 is the toggle being
    /// off, and its 28 and 32 would take minutes to hours on a phone, so
    /// `NostrPoW.miningTimeCap(forTargetBits:)` would step them down on every
    /// send anyway.
    static let difficultyLevels = [8, 12, 16, 20, 24]

    static var isEnabled: Bool {
        get { isEnabled(in: .standard) }
        set { setEnabled(newValue, in: .standard) }
    }

    static var difficultyBits: Int {
        get { difficultyBits(in: .standard) }
        set { setDifficultyBits(newValue, in: .standard) }
    }

    /// The NIP-13 target the next location-channel send commits to: the
    /// chosen difficulty, or 0 (no mining, no nonce tag) when off.
    static func sendTargetBits(in defaults: UserDefaults = .standard) -> Int {
        isEnabled(in: defaults) ? difficultyBits(in: defaults) : 0
    }

    // MARK: - Store-injecting forms

    /// These let tests assert the defaults and every setting without
    /// touching the shared preferences other tests read.
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: enabledKey)
    }

    /// A stored value that is not one of `difficultyLevels` (written by
    /// another build, or edited by hand) reads as the default.
    static func difficultyBits(in defaults: UserDefaults) -> Int {
        guard let stored = defaults.object(forKey: difficultyBitsKey) as? Int,
              difficultyLevels.contains(stored)
        else {
            return defaultDifficultyBits
        }
        return stored
    }

    /// Stores the offered level nearest to `bits` (the lower one on a tie).
    static func setDifficultyBits(_ bits: Int, in defaults: UserDefaults) {
        let level = difficultyLevels.min { abs($0 - bits) < abs($1 - bits) } ?? defaultDifficultyBits
        defaults.set(level, forKey: difficultyBitsKey)
    }

    /// Panic-wipe hook. Removing the keys restores the defaults, so a wiped
    /// device behaves like a fresh install.
    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: difficultyBitsKey)
    }
}
