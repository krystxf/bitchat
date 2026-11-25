//
// MessageRunPolicyTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
import Foundation
import BitFoundation
@testable import bitchat

struct MessageRunPolicyTests {
    private static let alice = PeerID(str: "00000000000000a1")
    private static let bob = PeerID(str: "00000000000000b1")

    private func row(
        _ sender: String,
        _ senderPeerID: PeerID?,
        at seconds: TimeInterval,
        id: String = UUID().uuidString
    ) -> BitchatMessage {
        BitchatMessage(
            id: id,
            sender: sender,
            content: "hi",
            timestamp: Date(timeIntervalSince1970: seconds),
            isRelay: false,
            senderPeerID: senderPeerID
        )
    }

    @Test func theFirstRowStartsARun() {
        #expect(MessageRunPolicy.startsRun(row("alice", Self.alice, at: 0), after: nil))
    }

    @Test func theSameSenderCloseInTimeContinuesTheRun() {
        let first = row("alice", Self.alice, at: 0)
        #expect(!MessageRunPolicy.startsRun(row("alice", Self.alice, at: 30), after: first))
    }

    @Test func anotherSenderStartsARunEvenUnderTheSameName() {
        let first = row("alice", Self.alice, at: 0)
        #expect(MessageRunPolicy.startsRun(row("bob", Self.bob, at: 1), after: first))
        // A namesake is someone else: their name must show again.
        #expect(MessageRunPolicy.startsRun(row("alice", Self.bob, at: 1), after: first))
    }

    @Test func aLongPauseStartsARun() {
        let first = row("alice", Self.alice, at: 0)
        let late = row("alice", Self.alice, at: MessageRunPolicy.maxGap + 1)
        #expect(MessageRunPolicy.startsRun(late, after: first))
    }

    @Test func systemLinesBreakRuns() {
        let first = row("alice", Self.alice, at: 0)
        let system = row("system", nil, at: 1)
        #expect(MessageRunPolicy.startsRun(system, after: first))
        #expect(MessageRunPolicy.startsRun(row("alice", Self.alice, at: 2), after: system))
    }

    @Test func archivedEchoesRunApartFromLiveRows() {
        let echo = row("alice", Self.alice, at: 0, id: BitchatMessage.archivedEchoIDPrefix + "1")
        #expect(MessageRunPolicy.startsRun(row("alice", Self.alice, at: 1), after: echo))
    }
}
