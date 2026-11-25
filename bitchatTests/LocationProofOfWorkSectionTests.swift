//
// LocationProofOfWorkSectionTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

@Suite("LocationProofOfWorkSection")
struct LocationProofOfWorkSectionTests {
    private typealias Estimate = LocationProofOfWorkSection.MiningTimeEstimate

    @Test func everyOfferedLevelGetsAnHonestEstimate() {
        // At the conservative hash rate: 256 and 4,096 hashes are instant,
        // 65,536 is a fraction of a second, and each further step is 16x.
        #expect(Estimate(targetBits: 8) == .instant)
        #expect(Estimate(targetBits: 12) == .instant)
        #expect(Estimate(targetBits: 16) == .underASecond)
        #expect(Estimate(targetBits: 20) == .about(seconds: Int(NostrPoW.estimatedMiningTime(forTargetBits: 20).rounded())))
        #expect(Estimate(targetBits: 24) == .about(seconds: Int(NostrPoW.estimatedMiningTime(forTargetBits: 24).rounded())))
    }

    @Test func longerLevelsNeverReadFasterThanShorterOnes() {
        func seconds(_ estimate: Estimate) -> Int {
            switch estimate {
            case .instant: return -2
            case .underASecond: return -1
            case .about(let seconds): return seconds
            }
        }
        let levels = LocationProofOfWorkSettings.difficultyLevels
        for (lower, higher) in zip(levels, levels.dropFirst()) {
            #expect(seconds(Estimate(targetBits: lower)) <= seconds(Estimate(targetBits: higher)))
        }
    }

    @Test func pickerLabelsNameTheBitsAndTheTime() {
        for bits in LocationProofOfWorkSettings.difficultyLevels {
            let label = LocationProofOfWorkSection.Strings.level(bits)
            #expect(label.contains(String(bits)))
            #expect(label.hasPrefix(LocationProofOfWorkSection.Strings.bitsLabel(bits)))
            #expect(label.hasSuffix(LocationProofOfWorkSection.Strings.estimate(Estimate(targetBits: bits))))
        }
    }

    @Test @MainActor func sectionRenders() {
        _ = LocationProofOfWorkSection().body
    }
}
