//
// ReactionLineVisibilityTests.swift
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
struct ReactionLineVisibilityTests {
    private let target = BitchatMessage(id: "t", sender: "ada", content: "hello there", timestamp: Date(), isRelay: false)

    @Test func everyReactionLineIsHiddenWhetherOrNotItResolves() {
        let add = BitchatMessage(sender: "bo", content: MessageReaction.format(emoji: "❤️", target: target), timestamp: Date(), isRelay: false)
        let removal = BitchatMessage(sender: "bo", content: MessageReaction.format(emoji: "❤️", target: target, removes: true), timestamp: Date(), isRelay: false)
        let wrongQuote = BitchatMessage(sender: "bo", content: add.content.replacingOccurrences(of: "hello there", with: "other text"), timestamp: Date(), isRelay: false)
        for line in [add, removal, wrongQuote] {
            #expect(line.isReactionLine)
            #expect(!MessageListScrollPolicy.isUnseenEligible(line))
        }
        let text = BitchatMessage(sender: "bo", content: "👍 reacted to \"hello there\"", timestamp: Date(), isRelay: false)
        #expect(!text.isReactionLine)
        #expect(MessageListScrollPolicy.isUnseenEligible(text))
    }
}
