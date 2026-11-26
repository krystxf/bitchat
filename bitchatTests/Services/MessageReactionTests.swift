import Foundation
import Testing
import BitFoundation
@testable import bitchat

struct MessageReactionTests {
    @Test func readableWireFormatRoundTrips() {
        let target = BitchatMessage(id: "nostr:event/1", sender: "Ada", content: "A useful message", timestamp: .now, isRelay: false)
        let wire = MessageReaction.format(emoji: "👍", target: target)
        #expect(wire.hasPrefix("👍 reacted to \"A useful message\" ⟨r:"))
        #expect(MessageReaction.parse(wire) == .init(emoji: "👍", targetID: target.id, removes: false))
    }

    @Test func acceptsOnlyCanonicalReactionLines() {
        let target = BitchatMessage(id: "target", sender: "Ada", content: "hello", timestamp: .now, isRelay: false)
        let valid = MessageReaction.format(emoji: "❤️", target: target)
        #expect(MessageReaction.parse(valid) != nil)
        #expect(MessageReaction.parse("❤️ reacted to \"hello\"" ) == nil)
        #expect(MessageReaction.parse(valid + " extra") == nil)
        #expect(MessageReaction.parse("Here is some text " + valid) == nil)
        #expect(MessageReaction.parse(valid.replacingOccurrences(of: "❤️", with: "ok")) == nil)
        #expect(MessageReaction.parse(valid.replacingOccurrences(of: "❤️", with: "👍👍")) == nil)
    }

    @Test(arguments: [
        "🙂",          // emoji presentation
        "❤️",          // text character made emoji with U+FE0F
        "©️",
        "1️⃣", "#️⃣",  // keycaps
        "👋🏽", "☝🏿",   // skin tones, on emoji and text-default bases
        "🇨🇿", "🇺🇳",   // flags
        "🏴󠁧󠁢󠁳󠁣󠁴󠁿",          // tag sequence (Scotland)
        "👩‍💻", "🏳️‍🌈", "🧑🏽‍🤝‍🧑🏻", "👨‍👩‍👧‍👦", "🏴‍☠️", // ZWJ sequences
    ])
    func anySingleEmojiReactsAndRoundTrips(_ emoji: String) {
        let target = BitchatMessage(id: "target", sender: "Ada", content: "hello", timestamp: .now, isRelay: false)
        #expect(MessageReaction.isReactionEmoji(emoji))
        let wire = MessageReaction.format(emoji: emoji, target: target)
        #expect(MessageReaction.parse(wire) == .init(emoji: emoji, targetID: "target", removes: false))
        let removal = MessageReaction.format(emoji: emoji, target: target, removes: true)
        #expect(MessageReaction.parse(removal) == .init(emoji: emoji, targetID: "target", removes: true))
    }

    @Test(arguments: [
        "", "a", "ok", "1", "#", "©", // text, digits, text-style symbols
        "👍👍", "🇨🇿🇩🇪", "👍 ", "a👍", // more than one cluster
        "👍\u{301}",  // a combining mark riding on an emoji
        "🇨",          // a lone regional indicator
        "❤︎",          // explicit text presentation
    ])
    func nonEmojiTextIsNoReaction(_ text: String) {
        let target = BitchatMessage(id: "target", sender: "Ada", content: "hello", timestamp: .now, isRelay: false)
        #expect(!MessageReaction.isReactionEmoji(text))
        #expect(MessageReaction.parse(MessageReaction.format(emoji: text, target: target)) == nil)
    }

    @Test func targetMustResolveAndQuoteMustMatch() {
        let target = BitchatMessage(id: "mesh:stable", sender: "Ada", content: "hello there", timestamp: .now, isRelay: false)
        let line = BitchatMessage(sender: "Bo", content: MessageReaction.format(emoji: "😂", target: target), timestamp: .now, isRelay: false)
        #expect(MessageReaction.resolvedEvents(in: [target, line]).count == 1)
        #expect(MessageReaction.resolvedEvents(in: [line]).isEmpty)
        let forged = BitchatMessage(sender: "Bo", content: line.content.replacingOccurrences(of: "hello there", with: "other text"), timestamp: .now, isRelay: false)
        #expect(MessageReaction.resolvedEvents(in: [target, forged]).isEmpty)
    }

    @Test func removalEventIsReadableAndRoundTrips() {
        let target = BitchatMessage(id: "event-id", sender: "Ada", content: "first message", timestamp: .now, isRelay: false)
        let wire = MessageReaction.format(emoji: "🙏", target: target, removes: true)
        #expect(wire.hasPrefix("🙏 removed reaction to \"first message\""))
        #expect(MessageReaction.parse(wire) == .init(emoji: "🙏", targetID: target.id, removes: true))
    }

    @Test func aggregationCountsDistinctPeopleAndTogglesRemoval() {
        let target = BitchatMessage(id: "target", sender: "Ada", content: "hello", timestamp: .now, isRelay: false)
        func event(_ sender: String, removes: Bool = false) -> (event: MessageReaction.Event, message: BitchatMessage) {
            let wire = MessageReaction.format(emoji: "👍", target: target, removes: removes)
            return (.init(emoji: "👍", targetID: target.id, removes: removes), BitchatMessage(sender: sender, content: wire, timestamp: .now, isRelay: false))
        }
        let active = MessageReaction.aggregate([event("Bo"), event("Cy"), event("Bo", removes: true)])
        #expect(active[target.id]?["👍"] == Set(["Cy"]))
    }
}
