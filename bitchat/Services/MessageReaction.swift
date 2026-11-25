import Foundation
import BitFoundation

/// A reaction is deliberately an ordinary, readable chat line. The exact
/// suffix carries the target ID; base64url keeps arbitrary transport IDs
/// compact and unambiguous without changing any wire protocol.
enum MessageReaction {
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
        guard emojis.contains(emoji), readable[closeQuote...].count == 1 else { return nil }
        return Event(emoji: emoji, targetID: targetID, removes: removes)
    }

    static func resolvedEvents(in messages: [BitchatMessage]) -> [(event: Event, message: BitchatMessage)] {
        let targets = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return messages.compactMap { message in
            guard let event = parse(message.content), let target = targets[event.targetID], target.id != message.id,
                  format(emoji: event.emoji, target: target, removes: event.removes) == message.content else { return nil }
            return (event, message)
        }
    }
}
