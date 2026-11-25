import Foundation
import BitFoundation

/// A reaction is deliberately an ordinary, readable chat line. The exact
/// suffix carries the target ID; base64url keeps arbitrary transport IDs
/// compact and unambiguous without changing any wire protocol.
enum MessageReaction {
    /// The quick reactions: the row in the message menu and the macOS
    /// quick bar. A reaction can be any single emoji (`isReactionEmoji`).
    static let emojis = ["❤️", "👍", "😂", "😮", "😢", "🙏"]
    private static let suffixPrefix = " ⟨r:"

    struct Event: Equatable {
        let emoji: String
        let targetID: String
        let removes: Bool
    }

    static func format(emoji: String, target: BitchatMessage, removes: Bool = false) -> String {
        let id = Data(target.id.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let quote = String(target.content.prefix(30)).replacingOccurrences(of: "\n", with: " ")
        let ending = target.content.count > 30 ? "…" : ""
        return "\(emoji) \(removes ? "removed reaction to" : "reacted to") \"\(quote)\(ending)\" ⟨r:\(removes ? "-" : "")\(id)⟩"
    }

    /// Accept only the formatter's canonical representation. In particular,
    /// the suffix ID must decode and re-encode identically.
    static func parse(_ text: String) -> Event? {
        guard let marker = text.range(of: suffixPrefix, options: .backwards),
              text.last == "⟩" else { return nil }
        let encoded = String(text[marker.upperBound..<text.index(before: text.endIndex)])
        let removes = encoded.hasPrefix("-")
        let token = removes ? String(encoded.dropFirst()) : encoded
        guard !token.isEmpty else { return nil }
        let base64 = token.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let targetID = String(data: data, encoding: .utf8),
              !targetID.isEmpty,
              Data(targetID.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == token else { return nil }
        let readable = String(text[..<marker.lowerBound])
        guard let split = readable.range(of: removes ? " removed reaction to \"" : " reacted to \""),
              let closeQuote = readable.lastIndex(of: "\""), closeQuote > split.upperBound else { return nil }
        let emoji = String(readable[..<split.lowerBound])
        guard isReactionEmoji(emoji), readable[closeQuote...].count == 1 else { return nil }
        return Event(emoji: emoji, targetID: targetID, removes: removes)
    }

    /// Whether `text` is exactly one emoji: one grapheme cluster that
    /// shows as an emoji. That covers emoji-presentation characters, text
    /// characters made emoji with U+FE0F, keycaps, skin-tone modifier
    /// sequences, flags, tag sequences and ZWJ sequences. Plain text, a
    /// bare digit or symbol, and two emojis are not.
    static func isReactionEmoji(_ text: String) -> Bool {
        guard text.count == 1, let first = text.unicodeScalars.first else { return false }
        let scalars = text.unicodeScalars
        let properties = first.properties
        // Flags: a pair of regional indicators.
        if (0x1F1E6...0x1F1FF).contains(first.value) {
            return scalars.count == 2 && scalars.allSatisfy { (0x1F1E6...0x1F1FF).contains($0.value) }
        }
        // Every scalar must belong to an emoji sequence, so a combining
        // mark or a letter cannot ride along in the same cluster.
        let isEmojiPart: (Unicode.Scalar) -> Bool = { scalar in
            scalar.properties.isEmoji
                || isNewerEmoji(scalar)
                || scalar.value == 0x200D // zero-width joiner
                || scalar.value == 0xFE0F // emoji presentation selector
                || scalar.value == 0x20E3 // combining enclosing keycap
                || (0xE0020...0xE007F).contains(scalar.value) // tags (subdivision flags)
        }
        guard properties.isEmoji || isNewerEmoji(first), scalars.allSatisfy(isEmojiPart) else { return false }
        if properties.isEmojiPresentation || isNewerEmoji(first) { return true }
        // A text-default character in emoji form: an explicit emoji
        // variation selector, a keycap, or a skin-tone modifier.
        return scalars.contains { scalar in
            scalar.value == 0xFE0F || scalar.value == 0x20E3 || scalar.properties.isEmojiModifier
        }
    }

    /// A code point this OS's Unicode tables do not know yet, in the
    /// blocks Unicode fills with new emoji. A reaction from a newer device
    /// then still reads as a reaction here, not as raw text.
    private static func isNewerEmoji(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F000...0x1FBFF).contains(scalar.value) && scalar.properties.generalCategory == .unassigned
    }

    static func resolvedEvents(in messages: [BitchatMessage]) -> [(event: Event, message: BitchatMessage)] {
        let targets = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return messages.compactMap { message in
            guard let event = parse(message.content), let target = targets[event.targetID], target.id != message.id,
                  format(emoji: event.emoji, target: target, removes: event.removes) == message.content else { return nil }
            return (event, message)
        }
    }

    /// Active actor IDs, aggregated once for an ordered conversation history.
    static func aggregate(_ events: [(event: Event, message: BitchatMessage)]) -> [String: [String: Set<String>]] {
        var owners: [String: [String: Set<String>]] = [:]
        for item in events {
            let owner = item.message.senderPeerID?.id ?? item.message.sender
            var active = owners[item.event.targetID, default: [:]][item.event.emoji, default: []]
            if item.event.removes { active.remove(owner) } else { active.insert(owner) }
            owners[item.event.targetID, default: [:]][item.event.emoji] = active
        }
        return owners
    }
}
