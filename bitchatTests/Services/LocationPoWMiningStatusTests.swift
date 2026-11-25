//
// LocationPoWMiningStatusTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

@Suite("LocationPoWMiningStatus")
@MainActor
struct LocationPoWMiningStatusTests {
    @Test func idleUntilASendBegins() {
        let status = LocationPoWMiningStatus()
        #expect(!status.isMining)
        #expect(status.miningSince == nil)
    }

    @Test func reportsTheOldestPendingSendUntilAllEnd() {
        let status = LocationPoWMiningStatus()
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 1_005)

        let firstID = status.beginMining(now: first)
        let secondID = status.beginMining(now: second)
        #expect(status.miningSince == first)

        // The queue moves on: the strip now times the next send.
        status.endMining(firstID)
        #expect(status.miningSince == second)

        status.endMining(secondID)
        #expect(!status.isMining)
    }

    @Test func sendsCanEndOutOfOrderAndTwice() {
        let status = LocationPoWMiningStatus()
        let first = Date(timeIntervalSince1970: 2_000)
        let firstID = status.beginMining(now: first)
        let secondID = status.beginMining(now: first.addingTimeInterval(1))

        status.endMining(secondID)
        #expect(status.miningSince == first)
        status.endMining(secondID)
        #expect(status.miningSince == first)

        status.endMining(firstID)
        #expect(!status.isMining)
    }
}
