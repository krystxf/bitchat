//
// VoiceLevelHistoryTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Combine
import Foundation
import Testing
@testable import bitchat

struct VoiceLevelHistoryTests {
    @Test func decibelsMapLinearlyAboveTheFloor() {
        #expect(VoiceLevelHistory.normalized(decibels: 0) == 1)
        #expect(VoiceLevelHistory.normalized(decibels: -25) == 0.5)
        #expect(VoiceLevelHistory.normalized(decibels: -50) == 0)
        #expect(VoiceLevelHistory.normalized(decibels: -160) == 0)
        #expect(VoiceLevelHistory.normalized(decibels: 6) == 1)
        #expect(VoiceLevelHistory.normalized(decibels: -.infinity) == 0)
        #expect(VoiceLevelHistory.normalized(decibels: .nan) == 0)
    }

    @Test func eachTickShowsOneQueuedLevel() {
        var history = VoiceLevelHistory(capacity: 10, maxBacklog: 4)
        history.enqueue(decibels: [0, -25, -50])

        history.tick()
        #expect(history.levels == [1])
        history.tick()
        #expect(history.levels == [1, 0.5])
        history.tick()
        #expect(history.levels == [1, 0.5, 0])
    }

    @Test func tickWithNothingQueuedHoldsStill() {
        var history = VoiceLevelHistory(capacity: 10, maxBacklog: 4)
        history.tick()
        #expect(history.levels.isEmpty)

        history.enqueue(decibels: [0])
        history.tick()
        history.tick()
        #expect(history.levels == [1])
    }

    @Test func backlogBeyondTheLimitDrainsAtOnce() {
        var history = VoiceLevelHistory(capacity: 10, maxBacklog: 2)
        // A late tap burst of five chunks: show three now, keep two queued.
        history.enqueue(decibels: [0, 0, 0, -25, -25])

        history.tick()
        #expect(history.levels == [1, 1, 1])
        history.tick()
        #expect(history.levels == [1, 1, 1, 0.5])
        history.tick()
        #expect(history.levels == [1, 1, 1, 0.5, 0.5])
    }

    @Test func oldLevelsScrollOffPastCapacity() {
        var history = VoiceLevelHistory(capacity: 3, maxBacklog: 0)
        history.enqueue(decibels: [0, -25, -50, -25])
        history.tick()

        #expect(history.levels == [0.5, 0, 0.5])
    }

    @Test func recentReturnsTheNewestLevelsOldestFirst() {
        var history = VoiceLevelHistory(capacity: 10, maxBacklog: 0)
        history.enqueue(decibels: [0, -25, -50])
        history.tick()

        #expect(Array(history.recent(2)) == [0.5, 0])
        #expect(Array(history.recent(10)) == [1, 0.5, 0])
        #expect(history.recent(0).isEmpty)
        #expect(history.recent(-1).isEmpty)
    }

    @Test func resetClearsShownAndQueuedLevels() {
        var history = VoiceLevelHistory(capacity: 10, maxBacklog: 4)
        history.enqueue(decibels: [0, 0, 0])
        history.tick()

        history.reset()
        history.tick()

        #expect(history.levels.isEmpty)
    }

    @Test @MainActor func meterPublishesOnlyWhenTheHistoryChanges() {
        let meter = VoiceLevelMeter()
        var changes = 0
        let subscription = meter.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        meter.ingest(decibels: [])
        meter.reset()
        #expect(changes == 0)

        meter.ingest(decibels: [-25])
        #expect(changes == 1)
        #expect(meter.history.levels == [0.5])

        meter.reset()
        #expect(changes == 2)
        #expect(meter.history.levels.isEmpty)
    }

    @Test func rmsConvertsToDecibelsWithASilenceFloor() {
        #expect(VoiceInputLevel.decibels(rms: 1) == 0)
        #expect(abs(VoiceInputLevel.decibels(rms: 0.1) - -20) < 0.001)
        #expect(VoiceInputLevel.decibels(rms: 0) == VoiceInputLevel.silenceDecibels)
        #expect(VoiceInputLevel.decibels(rms: .nan) == VoiceInputLevel.silenceDecibels)
    }

    @Test func tapBufferSplitsIntoRoundedChunks() {
        // 100 frames at a 40-frame chunk: 2.5 rounds to 3 chunks.
        let loud = [Float](repeating: 1, count: 50)
        let quiet = [Float](repeating: 0.1, count: 50)
        let levels = (loud + quiet).withUnsafeBufferPointer {
            VoiceInputLevel.chunkDecibels($0, chunkSize: 40)
        }

        #expect(levels.count == 3)
        #expect(levels[0] == 0)
        #expect(levels[2] < -19.9 && levels[2] > -20.1)
    }

    @Test func shortOrEmptyBuffersStillReport() {
        let short = [Float](repeating: 0.5, count: 10).withUnsafeBufferPointer {
            VoiceInputLevel.chunkDecibels($0, chunkSize: 1_920)
        }
        #expect(short.count == 1)

        let empty = [Float]().withUnsafeBufferPointer {
            VoiceInputLevel.chunkDecibels($0, chunkSize: 1_920)
        }
        #expect(empty.isEmpty)
    }
}
