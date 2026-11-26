//
// ExtremeSecuritySettingsTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

@Suite("ExtremeSecuritySettings")
struct ExtremeSecuritySettingsTests {
    /// Runs `body` against a private preferences suite and removes the suite
    /// afterwards, so no test reads or leaves the shared preferences.
    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "bitchat.tests.extreme-security.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test func modeIsOffByDefault() throws {
        // The mode deletes conversations for good, so only the user turns it on.
        try withIsolatedDefaults { defaults in
            #expect(!ExtremeSecuritySettings.isEnabled(in: defaults))
        }
    }

    @Test func theSettingRoundTrips() throws {
        try withIsolatedDefaults { defaults in
            ExtremeSecuritySettings.setEnabled(true, in: defaults)
            #expect(ExtremeSecuritySettings.isEnabled(in: defaults))

            ExtremeSecuritySettings.setEnabled(false, in: defaults)
            #expect(!ExtremeSecuritySettings.isEnabled(in: defaults))
        }
    }

    @Test func resetRestoresTheOffDefault() throws {
        // Panic wipe brings the device back like a fresh install, not with
        // the last choice.
        try withIsolatedDefaults { defaults in
            ExtremeSecuritySettings.setEnabled(true, in: defaults)

            ExtremeSecuritySettings.reset(in: defaults)

            #expect(!ExtremeSecuritySettings.isEnabled(in: defaults))
        }
    }
}
