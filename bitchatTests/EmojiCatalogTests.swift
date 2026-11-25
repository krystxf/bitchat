//
// EmojiCatalogTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

struct EmojiCatalogTests {
    private let catalog = EmojiCatalog.shared

    @Test func bundlesTheWholeUnicodeSetInUnicodeGroupOrder() {
        #expect(catalog.groups.map(\.kind) == EmojiGroup.allCases)
        // Emoji 18.0: 1,923 base emoji, 1,540 one-tone variants on 308 of
        // them. Mixed-tone sequences (two people, two tones) are left out.
        #expect(catalog.entryCount > 1_850)
        let withTones = catalog.groups.flatMap(\.entries).reduce(0) { $0 + 1 + $1.skinTones.count }
        #expect(withTones > 3_350)
    }

    @Test(arguments: ["😂", "❤️", "👩‍💻", "🏳️‍🌈", "🏴‍☠️", "🇨🇿", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "1️⃣", "#️⃣", "🧑‍🧑‍🧒‍🧒"])
    func holdsEveryKindOfEmoji(_ emoji: String) throws {
        let entry = try #require(catalog.entry(for: emoji))
        #expect(entry.emoji == emoji)
        #expect(MessageReaction.isReactionEmoji(emoji))
    }

    @Test func skinTonesRideOnTheirBaseEmoji() throws {
        let wave = try #require(catalog.entry(for: "👋"))
        #expect(wave.skinTones == ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])
        #expect(catalog.entry(for: "👋🏽")?.emoji == "👋")
        let coder = try #require(catalog.entry(for: "👩‍💻"))
        #expect(coder.skinTones.count == 5)
        #expect(catalog.entry(for: "😂")?.skinTones.isEmpty == true)
        // No variant has a grid cell of its own.
        #expect(!catalog.groups.flatMap(\.entries).contains { $0.emoji == "👋🏽" })
    }

    @Test func searchMatchesNamesAndKeywordsByWordPrefix() {
        #expect(catalog.search("tears of joy").first?.emoji == "😂")
        #expect(catalog.search("lol").contains { $0.emoji == "😂" })
        #expect(catalog.search("thumbs").first?.emoji == "👍")
        #expect(catalog.search("+1").contains { $0.emoji == "👍" })
        #expect(catalog.search("czech").contains { $0.emoji == "🇨🇿" })
        #expect(catalog.search("developer").contains { $0.emoji == "👩‍💻" })
        #expect(catalog.search("heart").first.map { $0.name.contains("heart") } == true)
        #expect(catalog.search("qqqzzz").isEmpty)
        #expect(catalog.search("  ").isEmpty)
        // An emoji finds its own entry, a skin tone its base.
        #expect(catalog.search("👋🏽").map(\.emoji) == ["👋"])
    }

    @Test func parsesTheGeneratedFormat() {
        let parsed = EmojiCatalog(tsv: """
        # comment
        @Smileys & Emotion
        ~face-smiling
        😀\tgrinning face\thappy smile\t1.0\t
        @People & Body
        ~hand-fingers-open
        👋\twaving hand\thello\t0.6\t👋🏻 👋🏼 👋🏽 👋🏾 👋🏿
        """)
        #expect(parsed.groups.map(\.kind) == [.smileysEmotion, .peopleBody])
        #expect(parsed.groups[0].entries.first?.subgroup == "face-smiling")
        #expect(parsed.groups[1].entries.first?.skinTones.count == 5)
        #expect(parsed.groups[1].entries.first?.version == 0.6)
    }

    @Test func rendersOnlyWhatTheEmojiFontDrawsAsOneGlyph() {
        #expect(EmojiRenderSupport.canRender("😀"))
        #expect(EmojiRenderSupport.canRender("👩‍💻"))
        #expect(EmojiRenderSupport.canRender("🇨🇿"))
        // Two emoji glued with a joiner that no font has a glyph for.
        #expect(!EmojiRenderSupport.canRender("🦒\u{200D}🍕"))
        // Unicode's newest version against an OS that may not know it:
        // the filter only ever drops entries newer than iOS 16's set.
        let filtered = EmojiCatalog(tsv: "@Symbols\n~test\n🦒\u{200D}🍕\tnot an emoji\t\t99.0\t\n😀\tgrinning face\t\t1.0\t\n")
            .filtered(EmojiRenderSupport.canRender)
        #expect(filtered.groups.first?.entries.map(\.emoji) == ["😀"])
    }
}
