//
// MediaRevealSettingsTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

@Suite("MediaRevealSettings")
struct MediaRevealSettingsTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "bitchat.tests.media-reveal.\(UUID().uuidString)")!
    }

    @Test func favoritesStayBlurredByDefault() {
        // Revealing anything without a tap must be an explicit choice.
        #expect(!MediaRevealSettings.autoRevealFavorites(in: isolatedDefaults()))
    }

    @Test func theSettingRoundTrips() {
        let defaults = isolatedDefaults()

        MediaRevealSettings.setAutoRevealFavorites(true, in: defaults)
        #expect(MediaRevealSettings.autoRevealFavorites(in: defaults))

        // Panic wipe restores the blurred default rather than the last choice.
        MediaRevealSettings.reset(in: defaults)
        #expect(!MediaRevealSettings.autoRevealFavorites(in: defaults))
    }
}
