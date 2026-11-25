//
// AppLanguageSettingsTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

@Suite("AppLanguageSettings")
struct AppLanguageSettingsTests {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "bitchat.tests.app-language.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func clearsWhatTheOldInAppPickerStored() {
        let (defaults, suite) = isolatedDefaults()
        defaults.set("de", forKey: "app.languageOverride")
        defaults.set(["de"], forKey: "AppleLanguages")

        AppLanguageSettings.clearLegacyOverride(in: defaults)

        // Read the suite's own values: a plain lookup of AppleLanguages
        // falls through to the global domain's system languages.
        let stored = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(stored["app.languageOverride"] == nil)
        #expect(stored["AppleLanguages"] == nil)
    }

    @Test func leavesASystemChosenLanguageAlone() {
        // Without the old picker's key, AppleLanguages came from the system
        // per-app language setting and must stay.
        let (defaults, _) = isolatedDefaults()
        defaults.set(["cs"], forKey: "AppleLanguages")

        AppLanguageSettings.clearLegacyOverride(in: defaults)

        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["cs"])
    }
}
