//
// ReactionOrphanStoreTests.swift
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
struct ReactionOrphanStoreTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTarget(_ id: String = "target", timestamp: TimeInterval = 0) -> BitchatMessage {
        BitchatMessage(
            id: id,
            sender: "ada",
            content: "the message everyone reacts to",
            timestamp: Self.start.addingTimeInterval(timestamp),
            isRelay: false,
            senderPeerID: PeerID(str: "peer-ada")
        )
    }

    private func reaction(
        _ id: String,
        to target: BitchatMessage,
        emoji: String = "👍",
        removes: Bool = false,
        sender: String = "bo",
        timestamp: TimeInterval = 10
    ) -> BitchatMessage {
        BitchatMessage(
            id: id,
            sender: sender,
            content: MessageReaction.format(emoji: emoji, target: target, removes: removes),
            timestamp: Self.start.addingTimeInterval(timestamp),
            isRelay: false,
            senderPeerID: PeerID(str: "peer-\(sender)")
        )
    }

    // MARK: Conversation store

    @Test func orphanStaysOutOfTheTimelineAndAttachesWhenItsTargetArrives() {
        let store = ConversationStore()
        store.append(BitchatMessage(id: "other", sender: "cy", content: "hi", timestamp: Self.start, isRelay: false), to: .mesh)
        let target = makeTarget(timestamp: 5)
        let orphan = reaction("r1", to: target)

        #expect(!store.append(orphan, to: .mesh))
        #expect(orphan.isReactionLine)
        #expect(store.conversation(for: .mesh).messages.map(\.id) == ["other"])
        #expect(store.reactionOrphans.count(in: .mesh) == 1)

        // History sync brings the target later.
        #expect(store.append(target, to: .mesh))
        #expect(store.conversation(for: .mesh).messages.map(\.id) == ["other", "target", "r1"])
        #expect(store.reactionOrphans.count == 0)
        let events = MessageReaction.resolvedEvents(in: store.conversation(for: .mesh).messages)
        #expect(events.map(\.event) == [.init(emoji: "👍", targetID: "target", removes: false)])
    }

    @Test func removalOrphanIsHeldAndKeepsItsOrderWhenAttached() {
        let store = ConversationStore()
        let target = makeTarget()
        store.append(reaction("add", to: target, timestamp: 10), to: .mesh)
        store.append(reaction("remove", to: target, removes: true, timestamp: 20), to: .mesh)
        #expect(store.reactionOrphans.count(in: .mesh) == 2)

        store.append(target, to: .mesh)
        let messages = store.conversation(for: .mesh).messages
        #expect(messages.map(\.id) == ["target", "add", "remove"])
        #expect(MessageReaction.aggregate(MessageReaction.resolvedEvents(in: messages))["target"]?["👍"] == [])
    }

    @Test func reactionToALoadedMessageGoesStraightIntoTheTimeline() {
        let store = ConversationStore()
        let target = makeTarget()
        store.append(target, to: .mesh)
        #expect(store.append(reaction("r1", to: target), to: .mesh))
        #expect(store.reactionOrphans.count == 0)
    }

    @Test func orphanOpensNoConversation() {
        let store = ConversationStore()
        let chat = ConversationID.directPeer(PeerID(str: "peer-bo"))
        store.upsertByID(reaction("r1", to: makeTarget()), in: chat)
        #expect(store.conversationsByID[chat] == nil)
        #expect(store.reactionOrphans.count(in: chat) == 1)
    }

    @Test func clearingAndWipingDropWaitingReactions() {
        let store = ConversationStore()
        let chat = ConversationID.directPeer(PeerID(str: "peer-bo"))
        store.append(makeTarget("shown"), to: .mesh)
        store.append(reaction("r1", to: makeTarget()), to: .mesh)
        store.append(reaction("r2", to: makeTarget()), to: chat)

        store.clear(.mesh)
        #expect(store.reactionOrphans.count(in: .mesh) == 0)
        #expect(store.reactionOrphans.count(in: chat) == 1)

        // Panic wipe and the extreme security exit both empty the store.
        store.clearAll()
        #expect(store.reactionOrphans.count == 0)
    }

    @Test func waitingReactionsFollowAMigratedConversation() {
        let store = ConversationStore()
        let ephemeral = ConversationID.directPeer(PeerID(str: "peer-short"))
        let stable = ConversationID.directPeer(PeerID(str: "peer-stable"))
        let target = makeTarget()
        store.append(makeTarget("hello"), to: ephemeral)
        store.append(reaction("r1", to: target), to: ephemeral)
        store.append(target, to: stable)

        store.migrateConversation(from: ephemeral, to: stable)
        #expect(store.reactionOrphans.count == 0)
        #expect(store.conversation(for: stable).containsMessage(withID: "r1"))
    }

    // MARK: Bounds

    @Test func holdsAtMostTheCapacityPerConversation() {
        var orphans = ReactionOrphanStore(capacityPerConversation: 3, totalCapacity: 100)
        let target = makeTarget()
        for index in 0..<5 {
            orphans.hold(reaction("r\(index)", to: target), targetID: "target", in: .mesh, now: Self.start)
        }
        #expect(orphans.count(in: .mesh) == 3)
        let released = orphans.release(targetID: "target", in: .mesh, now: Self.start)
        #expect(released.map(\.id) == ["r2", "r3", "r4"])
    }

    @Test func holdsAtMostTheTotalCapacityAcrossConversations() {
        var orphans = ReactionOrphanStore(capacityPerConversation: 10, totalCapacity: 3)
        let target = makeTarget()
        orphans.hold(reaction("old", to: target), targetID: "target", in: .mesh, now: Self.start)
        for index in 0..<3 {
            orphans.hold(
                reaction("dm\(index)", to: target),
                targetID: "target",
                in: .directPeer(PeerID(str: "peer-\(index)")),
                now: Self.start.addingTimeInterval(Double(index + 1))
            )
        }
        #expect(orphans.count == 3)
        #expect(orphans.count(in: .mesh) == 0)
    }

    @Test func linesExpireAfterTheAgeLimit() {
        var orphans = ReactionOrphanStore(maxAge: 60)
        let target = makeTarget()
        orphans.hold(reaction("r1", to: target), targetID: "target", in: .mesh, now: Self.start)
        let released = orphans.release(targetID: "target", in: .mesh, now: Self.start.addingTimeInterval(61))
        #expect(released.isEmpty)
        #expect(orphans.count == 0)
    }

    @Test func expiredLinesNeverAttach() {
        let store = ConversationStore()
        var now = Self.start
        store.reactionOrphanClock = { now }
        let target = makeTarget()
        store.append(reaction("r1", to: target), to: .mesh)

        now = now.addingTimeInterval(ReactionOrphanStore.defaultMaxAge + 1)
        store.append(target, to: .mesh)
        #expect(store.conversation(for: .mesh).messages.map(\.id) == ["target"])
    }

    @Test func holdingTheSameLineTwiceKeepsOneCopy() {
        var orphans = ReactionOrphanStore()
        let line = reaction("r1", to: makeTarget())
        let first = orphans.hold(line, targetID: "target", in: .mesh, now: Self.start)
        let second = orphans.hold(line, targetID: "target", in: .mesh, now: Self.start)
        #expect(first)
        #expect(!second)
        #expect(orphans.count == 1)
    }
}
