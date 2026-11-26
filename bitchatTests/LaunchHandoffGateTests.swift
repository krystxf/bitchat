//
// LaunchHandoffGateTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
@testable import bitchat

@Suite("LaunchHandoffGate")
@MainActor
struct LaunchHandoffGateTests {
    @Test func startsUnclaimed() {
        #expect(!LaunchHandoffGate().isClaimed)
    }

    @Test func onlyTheFirstWindowGetsTheHandoff() {
        let gate = LaunchHandoffGate()

        #expect(gate.claim())
        #expect(gate.isClaimed)
        // A second window, a reconnected scene, or a return from the
        // background must not replay it.
        #expect(!gate.claim())
        #expect(!gate.claim())
    }
}
