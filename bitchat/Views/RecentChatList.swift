//
// RecentChatList.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// "chats" section for the people sheet: direct conversations with people
/// who are not in any roster above it (offline passersby, geoDMs from a
/// channel since left). Before this section existed, those threads were
/// unreachable the moment the unread envelope cleared — still in memory,
/// no row anywhere in the UI. Renders nothing when there are none.
struct RecentChatList: View {
    @ThemedPalette private var palette

    let chats: [RecentChatRow]
    let onTapChat: (PeerID) -> Void

    private enum Strings {
        static let header = String(localized: "chats.section.header", defaultValue: "chats", comment: "Section header above recent direct conversations in the people sheet")
        static let unread = String(localized: "mesh_peers.state.unread", comment: "State label for a peer with unread private messages")
        static let openChatHint = String(localized: "chats.accessibility.open_hint", defaultValue: "opens this conversation", comment: "Accessibility hint on a recent chat row explaining activation opens the direct conversation")
    }

    /// Relative "5 min ago" stamps; the formatter is locale-aware.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        if !chats.isEmpty {
            Section {
                ForEach(chats) { chat in
                    Button {
                        onTapChat(chat.peerID)
                    } label: {
                        PeopleRow(
                            systemImage: "bubble.left.and.bubble.right",
                            iconColor: palette.secondary,
                            subtitle: lastActivityText(for: chat)
                        ) {
                            PeopleRowName(name: chat.displayName)
                        } accessories: {
                            if chat.hasUnread {
                                PeopleUnreadIndicator()
                            }
                        }
                    }
                    .peopleRowButtonStyle()
                    .accessibilityLabel(accessibilityDescription(for: chat))
                    .accessibilityHint(Strings.openChatHint)
                }
            } header: {
                Text(verbatim: Strings.header)
            }
        }
    }

    private func lastActivityText(for chat: RecentChatRow) -> String {
        Self.relativeFormatter.localizedString(for: chat.lastActivity, relativeTo: Date())
    }

    private func accessibilityDescription(for chat: RecentChatRow) -> String {
        var parts: [String] = [chat.displayName, lastActivityText(for: chat)]
        if chat.hasUnread { parts.append(Strings.unread) }
        return parts.joined(separator: ", ")
    }
}
