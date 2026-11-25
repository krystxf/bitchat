//
// LocationPoWMiningStatusTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

@Suite("LocationPoWMiningStatus")
@MainActor
struct LocationPoWMiningStatusTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func idleUntilASendBegins() {
        let status = LocationPoWMiningStatus()
        #expect(!status.isMining)
        #expect(status.miningSince == nil)
        #expect(status.send(for: "x") == nil)
    }

    @Test func aSendMinesFinishesAndEnds() {
        let status = LocationPoWMiningStatus()
        status.begin(messageID: "a", targetBits: 20, now: start)
        #expect(status.isMining)
        #expect(status.miningSince == start)
        #expect(status.send(for: "a")?.pace == PoWSendProgress.pace(forTargetBits: 20))

        status.finish(messageID: "a", now: start.addingTimeInterval(2))
        #expect(!status.isMining)
        #expect(status.send(for: "a")?.finishedAt == start.addingTimeInterval(2))
        // Finishing twice keeps the first time.
        status.finish(messageID: "a", now: start.addingTimeInterval(9))
        #expect(status.send(for: "a")?.finishedAt == start.addingTimeInterval(2))

        status.end(messageID: "a")
        #expect(status.sends.isEmpty)
    }

    @Test func miningSinceIsTheOldestSendStillMining() {
        let status = LocationPoWMiningStatus()
        status.begin(messageID: "a", targetBits: 8, now: start)
        status.begin(messageID: "b", targetBits: 8, now: start.addingTimeInterval(5))
        #expect(status.miningSince == start)
        status.finish(messageID: "a", now: start.addingTimeInterval(6))
        #expect(status.miningSince == start.addingTimeInterval(5))
    }

    @Test func progressShowsOnlyForSendsThatOutlastTheRevealDelay() {
        let status = LocationPoWMiningStatus()
        let reveal = PoWSendProgress.revealDelay

        // The default 8 bits: done in a moment, nothing ever showed.
        status.begin(messageID: "quick", targetBits: 8, now: start)
        status.finish(messageID: "quick", now: start.addingTimeInterval(0.002))
        #expect(!status.showedProgress(for: "quick", now: start.addingTimeInterval(10)))

        status.begin(messageID: "slow", targetBits: 20, now: start)
        #expect(!status.showedProgress(for: "slow", now: start.addingTimeInterval(reveal / 2)))
        #expect(status.showedProgress(for: "slow", now: start.addingTimeInterval(reveal)))

        #expect(!status.showedProgress(for: "unknown"))
    }

    @Test func paceFollowsTheDifficultyWithinTheCap() {
        // Never under half a second, even where mining takes a millisecond.
        #expect(PoWSendProgress.pace(forTargetBits: 8) == 0.5)
        #expect(PoWSendProgress.pace(forTargetBits: 20) == NostrPoW.estimatedMiningTime(forTargetBits: 20))
        // At 24 bits the expected time passes the cap; pace by the cap.
        #expect(PoWSendProgress.pace(forTargetBits: 24) == NostrPoW.miningTimeCap(forTargetBits: 24) / 3)
        let levels = LocationProofOfWorkSettings.difficultyLevels
        for (lower, higher) in zip(levels, levels.dropFirst()) {
            #expect(PoWSendProgress.pace(forTargetBits: lower) <= PoWSendProgress.pace(forTargetBits: higher))
        }
    }

    @Test func onlyMyLocationMessagesThatNeverWentOutCountAsUnsent() {
        func message(peer: PeerID?, isPrivate: Bool = false, status: DeliveryStatus?) -> BitchatMessage {
            BitchatMessage(
                sender: "me#2222", content: "hi", timestamp: start, isRelay: false,
                isPrivate: isPrivate, senderPeerID: peer, deliveryStatus: status
            )
        }
        let geo = PeerID(nostr: String(repeating: "2", count: 64))
        #expect(message(peer: geo, status: .sending).isUnsentLocationMessage)
        #expect(message(peer: geo, status: .failed(reason: "x")).isUnsentLocationMessage)
        #expect(!message(peer: geo, status: nil).isUnsentLocationMessage)
        #expect(!message(peer: PeerID(str: "0011223344556677"), status: .sending).isUnsentLocationMessage)
        #expect(!message(peer: geo, isPrivate: true, status: .failed(reason: "x")).isUnsentLocationMessage)
    }
}
