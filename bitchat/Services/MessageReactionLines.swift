//
// MessageReactionLines.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation

extension MessageReaction {
    /// The reaction a chat line carries, or nil for ordinary text. Wraps
    /// `parse(_:)` with a cheap first check: every reaction line ends with
    /// the closing bracket of its suffix, and most messages do not.
    static func event(in content: String) -> Event? {
        guard content.last == "⟩" else { return nil }
        return parse(content)
    }
}

extension MessageReaction {
    /// The alert for `line` when it adds a reaction to one of my messages in
    /// `conversation`: "Alice Reacted 👍 to Your Message". Nil for ordinary
    /// text, a removal, a reaction to someone else's message, and one whose
    /// target is not loaded.
    static func alertText(
        for line: BitchatMessage,
        in conversation: [BitchatMessage],
        isMine: (BitchatMessage) -> Bool
    ) -> String? {
        guard let event = event(in: line.content), !event.removes,
              let target = conversation.last(where: { $0.id == event.targetID }),
              target.id != line.id,
              format(emoji: event.emoji, target: target) == line.content,
              isMine(target) else { return nil }
        return String(
            format: String(
                localized: "notification.reaction.body",
                comment: "Alert for a reaction to one of my messages; placeholders are the person's name and the emoji"
            ),
            locale: .current,
            line.sender,
            event.emoji
        )
    }
}

extension BitchatMessage {
    /// Whether the message is a reaction line (`MessageReaction`): an add or
    /// a removal, with or without its target at hand. Such a line never
    /// shows as text. It does not count as unread, does not preview, and
    /// does not alert like a message.
    var isReactionLine: Bool {
        MessageReaction.event(in: content) != nil
    }
}
