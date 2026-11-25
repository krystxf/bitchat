//
// MessageReactionSummaryTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

@MainActor
struct MessageReactionSummaryTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let target = BitchatMessage(id: "target", sender: "ada", content: "hello", timestamp: Date(timeIntervalSince1970: 1_700_000_000), isRelay: false)

    private func line(_ emoji: String, from sender: String, removes: Bool = false, at offset: TimeInterval) -> BitchatMessage {
        BitchatMessage(
            sender: sender,
            content: MessageReaction.format(emoji: emoji, target: target, removes: removes),
            timestamp: start.addingTimeInterval(offset),
            isRelay: false,
            senderPeerID: PeerID(str: "peer-\(sender)")
        )
    }

    private func project(_ messages: [BitchatMessage]) -> [MessageReactionSummary] {
        MessageReactionProjection(
            messages: messages,
            isMine: { $0.sender == "me" },
            displayName: { $0.sender }
        ).summaries(for: "target")
    }

    @Test func pillsKeepTheOrderEachEmojiFirstArrivedIn() {
        let summaries = project([
            target,
            line("😂", from: "bo", at: 1),
            line("❤️", from: "cy", at: 2),
            line("😂", from: "me", at: 3),
            line("👍", from: "di", at: 4),
        ])
        #expect(summaries.map(\.emoji) == ["😂", "❤️", "👍"])
        #expect(summaries.first == MessageReactionSummary(emoji: "😂", otherNames: ["bo"], includesMe: true))
        #expect(summaries.first?.count == 2)
    }

    @Test func aTakenBackReactionLeavesNoPill() {
        let summaries = project([
            target,
            line("😂", from: "bo", at: 1),
            line("❤️", from: "me", at: 2),
            line("❤️", from: "me", removes: true, at: 3),
        ])
        #expect(summaries.map(\.emoji) == ["😂"])
    }

    @Test func namesReadAsAList() {
        func list(_ names: [String], me: Bool = false) -> String {
            MessageReactionNames.list(otherNames: names, includesMe: me, you: "You", others: { "\($0) Others" })
        }
        #expect(list(["Alice"]) == "Alice")
        #expect(list(["Alice", "Bob"]) == ListFormatter.localizedString(byJoining: ["Alice", "Bob"]))
        #expect(list(["Alice", "Bob"], me: true) == ListFormatter.localizedString(byJoining: ["You", "Alice", "Bob"]))
        #expect(list(["Alice", "Bob", "Cy", "Dee", "Eve"]) == ListFormatter.localizedString(byJoining: ["Alice", "Bob", "3 Others"]))
        #expect(list(["Alice", "Bob", "Cy"], me: true) == ListFormatter.localizedString(byJoining: ["You", "Alice", "2 Others"]))
    }
}
