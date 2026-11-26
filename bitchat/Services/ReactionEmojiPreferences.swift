//
// ReactionEmojiPreferences.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// What the reaction picker remembers on this device: the emoji I react
/// with most ("Frequently Used") and the skin tone I last chose for each
/// emoji that has them. Both go with the message wipes. Used from the
/// main thread (the picker and the wipes).
final class ReactionEmojiPreferences: ObservableObject {
    static let shared = ReactionEmojiPreferences(defaults: .standard)

    /// Emoji shown under Frequently Used.
    static let frequentLimit = 24
    /// Scores kept; the rest fall off.
    private static let scoreLimit = 64
    /// Each use weighs a little less than the next one, so recent use wins
    /// over a burst long ago.
    private static let decay = 0.95

    private static let scoresKey = "reactions.emojiScores"
    private static let tonesKey = "reactions.skinTones"

    private let defaults: UserDefaults
    @Published private(set) var frequent: [String] = []
    private var scores: [String: Double]
    private var tones: [String: String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        scores = defaults.dictionary(forKey: Self.scoresKey) as? [String: Double] ?? [:]
        tones = defaults.dictionary(forKey: Self.tonesKey) as? [String: String] ?? [:]
        frequent = Self.ranked(scores)
    }

    /// Counts a reaction I sent.
    func recordUse(_ emoji: String) {
        guard MessageReaction.isReactionEmoji(emoji) else { return }
        for key in scores.keys {
            scores[key]? *= Self.decay
        }
        scores[emoji, default: 0] += 1
        if scores.count > Self.scoreLimit {
            let kept = scores.sorted { $0.value > $1.value }.prefix(Self.scoreLimit)
            scores = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        defaults.set(scores, forKey: Self.scoresKey)
        frequent = Self.ranked(scores)
    }

    /// The emoji to show for `entry`: the skin tone I last chose, or the
    /// base emoji.
    func preferredVariant(of entry: EmojiCatalog.Entry) -> String {
        guard !entry.skinTones.isEmpty, let tone = tones[entry.emoji], entry.skinTones.contains(tone) else {
            return entry.emoji
        }
        return tone
    }

    /// Remembers `variant` (the base emoji itself or one of its skin
    /// tones) for `base`.
    func rememberVariant(_ variant: String, for base: String) {
        if variant == base {
            tones.removeValue(forKey: base)
        } else {
            tones[base] = variant
        }
        defaults.set(tones, forKey: Self.tonesKey)
        objectWillChange.send()
    }

    /// Frequently Used as the picker shows it: my own, topped up with the
    /// quick reactions while there are few.
    var frequentWithDefaults: [String] {
        var result = frequent
        for emoji in MessageReaction.emojis where result.count < 8 && !result.contains(emoji) {
            result.append(emoji)
        }
        return result
    }

    /// Forgets both (the message wipes).
    func removeAll() {
        scores.removeAll()
        tones.removeAll()
        defaults.removeObject(forKey: Self.scoresKey)
        defaults.removeObject(forKey: Self.tonesKey)
        frequent = []
    }

    private static func ranked(_ scores: [String: Double]) -> [String] {
        scores.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        .prefix(frequentLimit)
        .map(\.key)
    }
}
