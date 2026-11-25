//
// PeopleListOrderMemoryTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
@testable import bitchat

@MainActor
struct PeopleListOrderMemoryTests {

    @Test func firstRenderUsesProducerOrder() {
        let memory = PeopleListOrderMemory()
        #expect(memory.order(["c", "a", "b"]) == ["c", "a", "b"])
    }

    @Test func laterRendersKeepTheShownOrder() {
        let memory = PeopleListOrderMemory()
        _ = memory.order(["a", "b", "c"])
        // A heartbeat reordered the roster and someone new arrived.
        #expect(memory.order(["c", "d", "a", "b"]) == ["a", "b", "c", "d"])
    }

    @Test func repeatedRendersWithTheSameIDsAreStable() {
        let memory = PeopleListOrderMemory()
        _ = memory.order(["a", "b"])
        let first = memory.order(["b", "a", "c"])
        let second = memory.order(["b", "a", "c"])
        #expect(first == ["a", "b", "c"])
        #expect(second == first)
    }

    @Test func newGenerationShowsTheProducerOrderAgain() {
        let memory = PeopleListOrderMemory()
        _ = memory.order(["a", "b", "c"], generation: 0)
        #expect(memory.order(["c", "b", "a"], generation: 0) == ["a", "b", "c"])
        #expect(memory.order(["c", "b", "a"], generation: 1) == ["c", "b", "a"])
        // The same generation keeps the order it just showed.
        #expect(memory.order(["a", "c", "b"], generation: 1) == ["c", "b", "a"])
    }
}
