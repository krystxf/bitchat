//
// AvatarIdentity.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation

/// What an initials avatar shows for a person: up to two initials from
/// their name, on a color picked from their identity. Pure, so every view
/// that draws a person (bubbles, people lists) can agree on both.
///
/// ## Initials
///
/// 1. A trailing `#abcd` disambiguation suffix and any `@` are dropped.
/// 2. The name splits into words at every character that is not a letter
///    or a digit (spaces, punctuation, symbols, emoji), and where a
///    lowercase letter meets an uppercase one ("JohnDoe" is two words).
/// 3. Two or more words give the first character of the first two words:
///    "Alice Smith" → "AS", "john_doe" → "JD".
/// 4. One word gives its first character, plus the first digit after it if
///    there is one. The digit tells the many default "anonNNNN" names apart:
///    "anon9214" → "A9", "alice" → "A".
/// 5. Letters are uppercased. A name with nothing left gives "?".
///
/// ## Color
///
/// The same person gets the same color on every launch and every device.
/// A stable hash of their seed (`seed(for:nickname:)`) picks an entry of
/// `palette`: 64-bit FNV-1a over the seed's UTF-8 bytes, then the
/// MurmurHash3 final mix to spread it. Swift's `hashValue` must not be
/// used here: each process seeds it anew.
enum AvatarIdentity {
    /// An sRGB color with 8-bit channels.
    struct RGB: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        init(hex: UInt32) {
            red = UInt8((hex >> 16) & 0xFF)
            green = UInt8((hex >> 8) & 0xFF)
            blue = UInt8(hex & 0xFF)
        }
    }

    /// Avatar fills: twelve distinct hues, each dark enough for white
    /// initials at WCAG AA (4.5:1) in light and dark mode, and none near
    /// black, gray, or pale. `AvatarIdentityTests` checks all of this.
    /// Appending or reordering entries changes everyone's color.
    static let palette: [RGB] = [
        RGB(hex: 0xD32F2F), // red
        RGB(hex: 0xC2410C), // orange
        RGB(hex: 0xA16207), // amber
        RGB(hex: 0x4D7C0F), // olive
        RGB(hex: 0x15803D), // green
        RGB(hex: 0x0F766E), // teal
        RGB(hex: 0x0E7490), // cyan
        RGB(hex: 0x2563EB), // blue
        RGB(hex: 0x4F46E5), // indigo
        RGB(hex: 0x9333EA), // purple
        RGB(hex: 0xA21CAF), // magenta
        RGB(hex: 0xBE185D)  // pink
    ]

    // MARK: - Initials

    /// The initials for `name`, by the rules in the type's documentation.
    static func initials(for name: String) -> String {
        let (base, _) = name.splitSuffix()
        var words: [[Character]] = []
        var current: [Character] = []
        var previous: Character?
        for character in base {
            guard isNameCharacter(character) else {
                if !current.isEmpty { words.append(current) }
                current = []
                previous = nil
                continue
            }
            if let previous, previous.isLowercase, character.isUppercase {
                words.append(current)
                current = []
            }
            current.append(character)
            previous = character
            // Only the first two words count.
            if words.count == 2 { break }
        }
        if !current.isEmpty && words.count < 2 { words.append(current) }

        guard let first = words.first?.first else { return "?" }
        var picked = [first]
        if words.count >= 2, let second = words[1].first {
            picked.append(second)
        } else if let digit = words[0].dropFirst().first(where: \.isNumber) {
            picked.append(digit)
        }
        return picked.map(uppercased).joined()
    }

    /// Letters and digits make up words. Emoji do not, even those built on
    /// a digit (keycaps such as "1️⃣").
    private static func isNameCharacter(_ character: Character) -> Bool {
        guard character.isLetter || character.isNumber else { return false }
        return !character.unicodeScalars.contains { scalar in
            scalar.value == 0xFE0F || scalar.value == 0x20E3 || scalar.properties.isEmojiPresentation
        }
    }

    /// The character uppercased, unless that changes its length ("ß" would
    /// become "SS").
    private static func uppercased(_ character: Character) -> String {
        let upper = String(character).uppercased()
        return upper.count == 1 ? upper : String(character)
    }

    // MARK: - Color

    /// The seed that picks a person's color: their identity, written the
    /// same way wherever it shows up, or their nickname when there is no
    /// identity. Namesakes with distinct identities get distinct seeds.
    ///
    /// - A Noise key and the short mesh ID derived from it are one person.
    ///   So are a group member's ID (the same short ID) and their mesh ID.
    /// - A Nostr key shows as "nostr:" + 8 hex in a location channel and as
    ///   "nostr_" + 16 hex in its DMs. Both start with the same 8 hex.
    static func seed(for peerID: PeerID?, nickname: String) -> String {
        guard let peerID, !peerID.isEmpty else {
            return "name:" + nickname.normalizedNickname.lowercased()
        }
        switch peerID.prefix {
        case .geoChat, .geoDM:
            return "nostr:" + peerID.bare.prefix(8)
        case .bridge:
            return "bridge:" + peerID.bare
        case .group:
            return "group:" + peerID.bare
        case .name:
            return "name:" + peerID.bare.normalizedNickname
        case .empty, .mesh, .noise:
            return "mesh:" + peerID.toShort().bare
        }
    }

    /// The palette entry for `seed`.
    static func color(forSeed seed: String) -> RGB {
        palette[paletteIndex(forSeed: seed)]
    }

    // MARK: - Tile

    /// An avatar tile's two colors: the tile's fill, and the ink of the
    /// initials or glyph on it.
    struct Tile: Equatable {
        let fill: RGB
        let ink: RGB
    }

    /// The tile for `color`. Light mode puts the color, a shade deeper, on
    /// a light tint of it; dark mode puts a lighter shade on a deep tint
    /// over the charcoal backdrop. The ink reaches WCAG AA (4.5:1) on the
    /// fill for every palette entry (`AvatarIdentityTests`).
    static func tile(for color: RGB, isDark: Bool) -> Tile {
        if isDark {
            let charcoal = RGB(hex: NovaPalette.background.dark)
            return Tile(
                fill: mix(charcoal, color, amount: 0.28),
                ink: mix(color, RGB(hex: 0xFFFFFF), amount: 0.45)
            )
        }
        return Tile(
            fill: mix(RGB(hex: 0xFFFFFF), color, amount: 0.14),
            ink: mix(color, RGB(hex: 0x000000), amount: 0.12)
        )
    }

    /// `base` moved toward `other` by `amount` (0 keeps `base`).
    private static func mix(_ base: RGB, _ other: RGB, amount: Double) -> RGB {
        func channel(_ a: UInt8, _ b: UInt8) -> UInt32 {
            UInt32((Double(a) * (1 - amount) + Double(b) * amount).rounded())
        }
        return RGB(hex: channel(base.red, other.red) << 16
            | channel(base.green, other.green) << 8
            | channel(base.blue, other.blue))
    }

    static func paletteIndex(forSeed seed: String) -> Int {
        Int(finalMix(fnv1a64(seed)) % UInt64(palette.count))
    }

    /// 64-bit FNV-1a over the UTF-8 bytes of `text`.
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// The MurmurHash3 final mix (fmix64). FNV-1a mixes its last byte only
    /// into the low bits; seeds that differ only there (sequential IDs)
    /// would otherwise crowd a few palette entries.
    private static func finalMix(_ value: UInt64) -> UInt64 {
        var mixed = value
        mixed ^= mixed >> 33
        mixed = mixed &* 0xFF51_AFD7_ED55_8CCD
        mixed ^= mixed >> 33
        mixed = mixed &* 0xC4CE_B9FE_1A85_EC53
        mixed ^= mixed >> 33
        return mixed
    }
}
