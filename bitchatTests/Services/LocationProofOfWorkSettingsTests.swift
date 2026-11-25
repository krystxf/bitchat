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
        LocationProofOfWorkSettings.setHidesMessagesWithoutWork(true, in: defaults)

        LocationProofOfWorkSettings.reset(in: defaults)

        #expect(LocationProofOfWorkSettings.isEnabled(in: defaults))
        #expect(LocationProofOfWorkSettings.difficultyBits(in: defaults) == LocationProofOfWorkSettings.defaultDifficultyBits)
        #expect(!LocationProofOfWorkSettings.hidesMessagesWithoutWork(in: defaults))
    }

    // MARK: - Receive filter

    @Test func hidingMessagesWithoutWorkIsOffByDefault() {
        // On by default it would hide everyone on clients that mine nothing.
        #expect(!LocationProofOfWorkSettings.hidesMessagesWithoutWork(in: isolatedDefaults()))
    }

    @Test func hidingMessagesWithoutWorkRoundTripsIndependentlyOfSending() {
        let defaults = isolatedDefaults()
        LocationProofOfWorkSettings.setHidesMessagesWithoutWork(true, in: defaults)
        LocationProofOfWorkSettings.setEnabled(false, in: defaults)
        #expect(LocationProofOfWorkSettings.hidesMessagesWithoutWork(in: defaults))
        #expect(LocationProofOfWorkSettings.sendTargetBits(in: defaults) == 0)

        LocationProofOfWorkSettings.setHidesMessagesWithoutWork(false, in: defaults)
        #expect(!LocationProofOfWorkSettings.hidesMessagesWithoutWork(in: defaults))
        #expect(!LocationProofOfWorkSettings.isEnabled(in: defaults))
    }

    @Test func theIncomingMinimumMatchesTheRateLimitBypass() {
        #expect(LocationProofOfWorkSettings.minimumIncomingBits == NostrPoW.rateLimitBypassBits)
        #expect(LocationProofOfWorkSettings.minimumIncomingBits <= LocationProofOfWorkSettings.defaultDifficultyBits)
    }

    @Test func filterHidesOnlyMessagesBelowTheMinimum() async throws {
        let sender = try NostrIdentity.generate()

        let unmined = try NostrProtocol.createEphemeralGeohashEvent(content: "hi", geohash: "u4pruy", senderIdentity: sender)
        #expect(LocationProofOfWorkSettings.filterHides(unmined))

        let mined = try await NostrProtocol.createMinedEphemeralGeohashEvent(
            content: "hi", geohash: "u4pruy", senderIdentity: sender, powTargetBits: 8
        )
        try #require(NostrPoW.validatedDifficulty(idHex: mined.id, tags: mined.tags) == 8)
        #expect(!LocationProofOfWorkSettings.filterHides(mined))

        let weak = try await NostrProtocol.createMinedEphemeralGeohashEvent(
            content: "hi", geohash: "u4pruy", senderIdentity: sender, powTargetBits: 4
        )
        #expect(LocationProofOfWorkSettings.filterHides(weak))

        // Not messages: presence heartbeats and empty teleport markers.
        let presence = try NostrProtocol.createGeohashPresenceEvent(geohash: "u4pruy", senderIdentity: sender)
        #expect(!LocationProofOfWorkSettings.filterHides(presence))
        let teleportMarker = try NostrProtocol.createEphemeralGeohashEvent(
            content: "  ", geohash: "u4pruy", senderIdentity: sender, teleported: true
        )
        #expect(!LocationProofOfWorkSettings.filterHides(teleportMarker))
    }
}
