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

extension BitchatMessage {
    /// Whether the message is a reaction line (`MessageReaction`): an add or
    /// a removal, with or without its target at hand. Such a line never
    /// shows as text. It does not count as unread, does not preview, and
    /// does not alert like a message.
    var isReactionLine: Bool {
        MessageReaction.event(in: content) != nil
    }
}
