//
// ReactionEmojiPreferencesTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

struct ReactionEmojiPreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let name = "reaction-prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func frequentlyUsedRanksByUseAndFavorsRecentUse() {
        let preferences = ReactionEmojiPreferences(defaults: makeDefaults())
        #expect(preferences.frequent.isEmpty)
        #expect(Array(preferences.frequentWithDefaults.prefix(6)) == MessageReaction.emojis)

        for _ in 0..<3 { preferences.recordUse("🎉") }
        preferences.recordUse("👩‍💻")
        #expect(preferences.frequent == ["🎉", "👩‍💻"])
        #expect(preferences.frequentWithDefaults.first == "🎉")

        // Enough recent use overtakes an older burst.
        for _ in 0..<4 { preferences.recordUse("🇨🇿") }
        #expect(preferences.frequent.first == "🇨🇿")

        // Text is never recorded.
        preferences.recordUse("ok")
        #expect(!preferences.frequent.contains("ok"))
    }

    @Test func frequentlyUsedAndSkinTonesSurviveARelaunchAndGoWithTheWipe() throws {
        let defaults = makeDefaults()
        let wave = try #require(EmojiCatalog.shared.entry(for: "👋"))
        do {
            let preferences = ReactionEmojiPreferences(defaults: defaults)
            preferences.recordUse("🔥")
            preferences.rememberVariant("👋🏽", for: "👋")
            #expect(preferences.preferredVariant(of: wave) == "👋🏽")
        }
        let relaunched = ReactionEmojiPreferences(defaults: defaults)
        #expect(relaunched.frequent == ["🔥"])
        #expect(relaunched.preferredVariant(of: wave) == "👋🏽")

        relaunched.rememberVariant("👋", for: "👋")
        #expect(relaunched.preferredVariant(of: wave) == "👋")

        relaunched.rememberVariant("👋🏿", for: "👋")
        relaunched.removeAll()
        #expect(relaunched.frequent.isEmpty)
        #expect(relaunched.preferredVariant(of: wave) == "👋")
        #expect(ReactionEmojiPreferences(defaults: defaults).frequent.isEmpty)
    }

    @Test func anEmojiWithoutTonesIgnoresAStaleTone() throws {
        let preferences = ReactionEmojiPreferences(defaults: makeDefaults())
        let joy = try #require(EmojiCatalog.shared.entry(for: "😂"))
        preferences.rememberVariant("👋🏽", for: "😂")
        #expect(preferences.preferredVariant(of: joy) == "😂")
    }
}
