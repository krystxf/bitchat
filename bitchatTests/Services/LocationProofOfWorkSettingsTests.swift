//
// LocationProofOfWorkSettingsTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

@Suite("LocationProofOfWorkSettings")
struct LocationProofOfWorkSettingsTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "bitchat.tests.location-pow.\(UUID().uuidString)")!
    }

    @Test func defaultsKeepTheBehaviorFromBeforeTheSetting() {
        // Every location send mined 8 bits before the setting existed.
        let defaults = isolatedDefaults()
        #expect(LocationProofOfWorkSettings.isEnabled(in: defaults))
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == NostrPoW.targetBits)
        #expect(LocationProofOfWorkSettings.sendTargetBits(in: defaults) == NostrPoW.targetBits)
        // The default earns the receive-side rate-limit relief.
        #expect(LocationProofOfWorkSettings.defaultDifficultyBits >= NostrPoW.rateLimitBypassBits)
    }

    @Test func theDefaultIsOneOfTheOfferedLevels() {
        #expect(LocationProofOfWorkSettings.difficultyLevels.contains(LocationProofOfWorkSettings.defaultDifficultyBits))
        #expect(LocationProofOfWorkSettings.difficultyLevels == LocationProofOfWorkSettings.difficultyLevels.sorted())
    }

    @Test func theSettingsRoundTrip() {
        let defaults = isolatedDefaults()

        LocationProofOfWorkSettings.setDifficultyBits(20, in: defaults)
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == 20)
        #expect(LocationProofOfWorkSettings.sendTargetBits(in: defaults) == 20)

        LocationProofOfWorkSettings.setEnabled(false, in: defaults)
        #expect(!LocationProofOfWorkSettings.isEnabled(in: defaults))
        // Off means no mining at all, whatever difficulty is kept for later.
        #expect(LocationProofOfWorkSettings.sendTargetBits(in: defaults) == 0)
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == 20)

        LocationProofOfWorkSettings.setEnabled(true, in: defaults)
        #expect(LocationProofOfWorkSettings.sendTargetBits(in: defaults) == 20)
    }

    @Test func difficultySnapsToTheNearestOfferedLevel() {
        let defaults = isolatedDefaults()

        LocationProofOfWorkSettings.setDifficultyBits(13, in: defaults)
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == 12)
        LocationProofOfWorkSettings.setDifficultyBits(14, in: defaults)
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == 12)
        LocationProofOfWorkSettings.setDifficultyBits(0, in: defaults)
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == 8)
        LocationProofOfWorkSettings.setDifficultyBits(32, in: defaults)
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == 24)
    }

    @Test func aStoredValueOutsideTheLevelsReadsAsTheDefault() {
        let defaults = isolatedDefaults()
        defaults.set(31, forKey: "locationPoW.difficultyBits")
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == LocationProofOfWorkSettings.defaultDifficultyBits)
    }

    @Test func panicWipeRestoresTheDefaults() {
        let defaults = isolatedDefaults()
        LocationProofOfWorkSettings.setEnabled(false, in: defaults)
        LocationProofOfWorkSettings.setDifficultyBits(24, in: defaults)

        LocationProofOfWorkSettings.reset(in: defaults)

        #expect(LocationProofOfWorkSettings.isEnabled(in: defaults))
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == LocationProofOfWorkSettings.defaultDifficultyBits)
    }
}
