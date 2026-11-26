//
// AvatarIdentityTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
import Foundation
import BitFoundation
@testable import bitchat

struct AvatarIdentityTests {
    // MARK: - Initials

    @Test(arguments: [
        ("Alice Smith", "AS"),
        ("mary ann smith", "MA"),
        ("john_doe", "JD"),
        ("john.doe", "JD"),
        ("JohnDoe", "JD"),
        ("alice", "A"),
        ("DJ", "D"),
        ("anon9214", "A9"),
        ("bob2", "B2"),
        ("r2d2", "R2"),
        ("1234", "12"),
        ("иван петров", "ИП"),
        ("王小明", "王"),
        ("élodie", "É"),
        ("ßtraße", "ß")
    ])
    func initialsFollowTheWordRules(name: String, expected: String) {
        #expect(AvatarIdentity.initials(for: name) == expected)
    }

    @Test func theDisambiguationSuffixAndAtSignAreDropped() {
        #expect(AvatarIdentity.initials(for: "anon9214#a1b2") == "A9")
        #expect(AvatarIdentity.initials(for: "bob#c0ff") == "B")
        #expect(AvatarIdentity.initials(for: "@carol") == "C")
    }

    @Test func emojiAndWhitespaceAreSkipped() {
        #expect(AvatarIdentity.initials(for: "  🔥 blaze  ") == "B")
        #expect(AvatarIdentity.initials(for: "🔥blaze🔥runner") == "BR")
        #expect(AvatarIdentity.initials(for: "1️⃣ bob") == "B")
    }

    @Test(arguments: ["", "   ", "🔥🔥", "#!?", "#abcd"])
    func aNameWithNothingLeftGivesAQuestionMark(name: String) {
        #expect(AvatarIdentity.initials(for: name) == "?")
    }

    // MARK: - Seed

    @Test func aNostrKeyHasOneSeedInChannelsAndDMs() {
        let pubkey = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        let channel = AvatarIdentity.seed(for: PeerID(nostr: pubkey), nickname: "alice")
        let dm = AvatarIdentity.seed(for: PeerID(nostr_: pubkey), nickname: "alice")
        #expect(channel == dm)
        #expect(channel == "nostr:abcdef01")
    }

    @Test func aNoiseKeyAndItsShortIDHaveOneSeed() {
        let noiseKey = Data((0..<32).map { UInt8($0) })
        let short = PeerID(publicKey: noiseKey)
        let full = PeerID(str: "noise:" + noiseKey.hexEncodedString())
        #expect(AvatarIdentity.seed(for: full, nickname: "x") == AvatarIdentity.seed(for: short, nickname: "y"))
    }

    @Test func theSeedIgnoresTheNicknameWhenThereIsAnIdentity() {
        let peerID = PeerID(str: "00000000000000a1")
        #expect(AvatarIdentity.seed(for: peerID, nickname: "alice") == AvatarIdentity.seed(for: peerID, nickname: "alice2"))
    }

    @Test func aGroupKeepsItsSeedWhenRenamed() {
        let groupID = PeerID(groupID: Data(repeating: 0xAB, count: 16))
        let seed = AvatarIdentity.seed(for: groupID, nickname: "trip")
        #expect(seed == AvatarIdentity.seed(for: groupID, nickname: "weekend"))
        #expect(seed == "group:" + String(repeating: "ab", count: 16))
    }

    @Test func namesakesWithDistinctIdentitiesGetDistinctSeeds() {
        let one = AvatarIdentity.seed(for: PeerID(str: "00000000000000a1"), nickname: "alice")
        let two = AvatarIdentity.seed(for: PeerID(str: "00000000000000b1"), nickname: "alice")
        #expect(one != two)
    }

    @Test func withoutAnIdentityTheNicknameIsTheSeed() {
        // Case and Unicode normalization must not change the color.
        let composed = AvatarIdentity.seed(for: nil, nickname: "Café")
        let decomposed = AvatarIdentity.seed(for: nil, nickname: "cafe\u{0301}")
        #expect(composed == decomposed)
        #expect(AvatarIdentity.seed(for: PeerID(str: ""), nickname: "café") == composed)
    }

    // MARK: - Color

    @Test func fnv1aMatchesTheReferenceVectors() {
        #expect(AvatarIdentity.fnv1a64("") == 0xCBF2_9CE4_8422_2325)
        #expect(AvatarIdentity.fnv1a64("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(AvatarIdentity.fnv1a64("foobar") == 0x8594_4171_F739_67E8)
    }

    @Test func theSameSeedAlwaysGetsTheSameColor() {
        let seed = AvatarIdentity.seed(for: PeerID(str: "00000000000000a1"), nickname: "alice")
        let first = AvatarIdentity.color(forSeed: seed)
        for _ in 0..<10 {
            #expect(AvatarIdentity.color(forSeed: seed) == first)
        }
    }

    /// Pinned values: everyone's color must survive app updates and match
    /// across devices. A change here recolors every person.
    @Test func paletteIndicesAreStableAcrossReleases() {
        #expect(AvatarIdentity.paletteIndex(forSeed: "mesh:00000000000000a1") == Self.pinned["mesh:00000000000000a1"])
        #expect(AvatarIdentity.paletteIndex(forSeed: "nostr:abcdef01") == Self.pinned["nostr:abcdef01"])
        #expect(AvatarIdentity.paletteIndex(forSeed: "name:anon9214") == Self.pinned["name:anon9214"])
    }

    private static let pinned: [String: Int] = [
        "mesh:00000000000000a1": 11,
        "nostr:abcdef01": 3,
        "name:anon9214": 2
    ]

    @Test func sequentialIDsSpreadAcrossThePalette() {
        let seeds = (0..<2_400).map { String(format: "mesh:%016llx", $0) }
        expectEvenSpread(of: seeds)
    }

    @Test func defaultNicknamesSpreadAcrossThePalette() {
        let seeds = (0..<2_400).map { String(format: "name:anon%04d", $0) }
        expectEvenSpread(of: seeds)
    }

    private func expectEvenSpread(of seeds: [String]) {
        var counts = [Int](repeating: 0, count: AvatarIdentity.palette.count)
        for seed in seeds {
            counts[AvatarIdentity.paletteIndex(forSeed: seed)] += 1
        }
        let mean = Double(seeds.count) / Double(counts.count)
        for count in counts {
            #expect(Double(count) > mean * 0.7, "palette entry used \(count) times, mean \(mean)")
            #expect(Double(count) < mean * 1.3, "palette entry used \(count) times, mean \(mean)")
        }
    }

    // MARK: - Palette

    @Test func whiteInitialsMeetWCAGAAOnEveryPaletteColor() {
        for color in AvatarIdentity.palette {
            let ratio = contrastRatio(luminance(of: color), 1.0)
            #expect(ratio >= 4.5, "white on \(hex(color)) is \(ratio):1")
        }
    }

    @Test func noPaletteColorIsNearBlackGrayOrPale() {
        for color in AvatarIdentity.palette {
            // Near black would vanish on the dark backdrop.
            #expect(luminance(of: color) >= 0.1, "\(hex(color)) is too dark")
            let channels = [color.red, color.green, color.blue].map(Double.init)
            let chroma = (channels.max()! - channels.min()!) / 255
            #expect(chroma >= 0.35, "\(hex(color)) is too gray or pale")
        }
    }

    @Test func paletteHuesAreDistinct() {
        let hues = AvatarIdentity.palette.map(hue)
        for i in hues.indices {
            for j in hues.indices where j > i {
                let gap = abs(hues[i] - hues[j])
                #expect(min(gap, 360 - gap) >= 15, "\(hex(AvatarIdentity.palette[i])) and \(hex(AvatarIdentity.palette[j])) are too close")
            }
        }
    }

    @Test(arguments: [false, true])
    func tileInkMeetsWCAGAAOnEveryPaletteColor(isDark: Bool) {
        for color in AvatarIdentity.palette {
            let tile = AvatarIdentity.tile(for: color, isDark: isDark)
            let ratio = contrastRatio(luminance(of: tile.ink), luminance(of: tile.fill))
            #expect(ratio >= 4.5, "\(hex(tile.ink)) on \(hex(tile.fill)) is \(ratio):1 (dark: \(isDark))")
        }
    }

    @Test(arguments: [false, true])
    func tileKeepsTheColorsHue(isDark: Bool) {
        for color in AvatarIdentity.palette {
            let tile = AvatarIdentity.tile(for: color, isDark: isDark)
            for shade in [tile.fill, tile.ink] {
                let gap = abs(hue(of: shade) - hue(of: color))
                #expect(min(gap, 360 - gap) <= 20, "\(hex(shade)) strays from \(hex(color))")
            }
        }
    }

    // MARK: - Helpers

    /// WCAG 2 relative luminance.
    private func luminance(of color: AvatarIdentity.RGB) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private func contrastRatio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Hue in degrees.
    private func hue(of color: AvatarIdentity.RGB) -> Double {
        let r = Double(color.red) / 255, g = Double(color.green) / 255, b = Double(color.blue) / 255
        let maxValue = max(r, g, b), minValue = min(r, g, b)
        let delta = maxValue - minValue
        guard delta > 0 else { return 0 }
        var hue: Double
        if maxValue == r {
            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        hue *= 60
        return hue < 0 ? hue + 360 : hue
    }

    private func hex(_ color: AvatarIdentity.RGB) -> String {
        String(format: "#%02X%02X%02X", color.red, color.green, color.blue)
    }
}
