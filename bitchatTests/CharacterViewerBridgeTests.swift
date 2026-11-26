//
// CharacterViewerBridgeTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

#if os(macOS)
import Testing
@testable import bitchat

struct CharacterViewerBridgeTests {
    @Test func theFirstEmojiTypedIsThePickAndEndsTheWait() {
        let bridge = CharacterViewerBridge()
        var picked: [String] = []
        bridge.request { picked.append($0) }
        #expect(!bridge.deliver("a"))
        #expect(bridge.deliver("👩‍💻🎉"))
        #expect(picked == ["👩‍💻"])
        // Nothing waits any more.
        #expect(!bridge.deliver("🎉"))
        #expect(picked == ["👩‍💻"])
    }

    @Test func aCancelledWaitPicksNothing() {
        let bridge = CharacterViewerBridge()
        var picked: [String] = []
        bridge.request { picked.append($0) }
        bridge.cancel()
        #expect(!bridge.deliver("👍"))
        #expect(picked.isEmpty)
    }
}
#endif
