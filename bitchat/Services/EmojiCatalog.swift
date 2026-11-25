//
// EmojiCatalog.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreText
import Foundation

/// Unicode's groups, in Unicode's order (the Component group holds no
/// emoji of its own and is left out).
enum EmojiGroup: String, CaseIterable, Identifiable {
    case smileysEmotion = "Smileys & Emotion"
    case peopleBody = "People & Body"
    case animalsNature = "Animals & Nature"
    case foodDrink = "Food & Drink"
    case travelPlaces = "Travel & Places"
    case activities = "Activities"
    case objects = "Objects"
    case symbols = "Symbols"
    case flags = "Flags"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smileysEmotion: String(localized: "emoji.group.smileys_emotion", comment: "Emoji category title")
        case .peopleBody: String(localized: "emoji.group.people_body", comment: "Emoji category title")
        case .animalsNature: String(localized: "emoji.group.animals_nature", comment: "Emoji category title")
        case .foodDrink: String(localized: "emoji.group.food_drink", comment: "Emoji category title")
        case .travelPlaces: String(localized: "emoji.group.travel_places", comment: "Emoji category title")
        case .activities: String(localized: "emoji.group.activities", comment: "Emoji category title")
        case .objects: String(localized: "emoji.group.objects", comment: "Emoji category title")
        case .symbols: String(localized: "emoji.group.symbols", comment: "Emoji category title")
        case .flags: String(localized: "emoji.group.flags", comment: "Emoji category title")
        }
    }

    /// The category bar's symbol (all exist from iOS 16).
    var systemImage: String {
        switch self {
        case .smileysEmotion: "face.smiling"
        case .peopleBody: "person"
        case .animalsNature: "pawprint"
        case .foodDrink: "fork.knife"
        case .travelPlaces: "car"
        case .activities: "basketball"
        case .objects: "lightbulb"
        case .symbols: "heart"
        case .flags: "flag"
        }
    }
}

/// Every emoji the reaction picker offers: Unicode's full fully-qualified
/// set, generated from emoji-test.txt and CLDR's English keywords by
/// scripts/generate-emoji-catalog.py into Resources/Emoji/emoji-catalog.tsv.
/// Skin-tone variants ride on their base emoji instead of filling the grid.
struct EmojiCatalog {
    struct Entry: Identifiable, Hashable {
        let emoji: String
        let group: EmojiGroup
        let subgroup: String
        /// CLDR's short name, e.g. "face with tears of joy".
        let name: String
        /// Lowercased name and keywords, each word led by a space, for
        /// word-prefix search.
        let searchText: String
        /// The emoji version that added it, e.g. 15.1.
        let version: Double
        /// The five one-tone variants, light to dark; empty when none.
        let skinTones: [String]

        var id: String { emoji }
    }

    struct Group: Identifiable {
        let kind: EmojiGroup
        let entries: [Entry]
        var id: EmojiGroup { kind }
    }

    let groups: [Group]

    /// The bundled catalog, without the emoji this OS cannot draw. Parsed
    /// on first use.
    static let shared: EmojiCatalog = {
        guard let text = bundledText() else { return EmojiCatalog(groups: []) }
        return EmojiCatalog(tsv: text).filtered(EmojiRenderSupport.canRender)
    }()

    init(groups: [Group]) {
        self.groups = groups
    }

    /// Parses the generated catalog (see the generator for the format).
    init(tsv: String) {
        var groups: [Group] = []
        var group: EmojiGroup?
        var subgroup = ""
        var entries: [Entry] = []
        func closeGroup() {
            if let group, !entries.isEmpty { groups.append(Group(kind: group, entries: entries)) }
            entries = []
        }
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            // Comments start with "# "; the keycap "#️⃣" is one character.
            if line.hasPrefix("# ") { continue }
            if line.hasPrefix("@") {
                closeGroup()
                group = EmojiGroup(rawValue: String(line.dropFirst()))
                continue
            }
            if line.hasPrefix("~") {
                subgroup = String(line.dropFirst())
                continue
            }
            guard let group else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { continue }
            let name = String(fields[1])
            let keywords = String(fields[2])
            entries.append(Entry(
                emoji: String(fields[0]),
                group: group,
                subgroup: subgroup,
                name: name,
                searchText: " " + (name + " " + keywords).lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(["+", "'"]))
                    .filter { !$0.isEmpty }
                    .joined(separator: " "),
                version: Double(fields[3]) ?? 0,
                skinTones: fields.count > 4 ? fields[4].split(separator: " ").map(String.init) : []
            ))
        }
        closeGroup()
        self.groups = groups
    }

    var entryCount: Int { groups.reduce(0) { $0 + $1.entries.count } }

    /// The catalog without the emoji (or skin tones) `isSupported` rejects.
    func filtered(_ isSupported: (Entry) -> Bool) -> EmojiCatalog {
        EmojiCatalog(groups: groups.compactMap { group in
            let entries = group.entries.filter(isSupported)
            return entries.isEmpty ? nil : Group(kind: group.kind, entries: entries)
        })
    }

    /// Entries whose name or keywords hold every word of `query` as a word
    /// prefix ("thumb up", "laugh", "czech"). Name hits come first. An
    /// emoji typed into the field finds itself.
    func search(_ query: String, limit: Int = 300) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if MessageReaction.isReactionEmoji(trimmed) {
            return allEntries.filter { $0.emoji == trimmed || $0.skinTones.contains(trimmed) }
        }
        let tokens = trimmed.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(["+", "'"]))
            .filter { !$0.isEmpty }
            .map { " " + $0 }
        guard !tokens.isEmpty else { return [] }
        var nameHits: [Entry] = []
        var keywordHits: [Entry] = []
        for entry in allEntries where tokens.allSatisfy({ entry.searchText.contains($0) }) {
            let nameText = " " + entry.name.lowercased()
            if tokens.allSatisfy({ nameText.contains($0) }) {
                nameHits.append(entry)
            } else {
                keywordHits.append(entry)
            }
            if nameHits.count >= limit { break }
        }
        return Array((nameHits + keywordHits).prefix(limit))
    }

    /// The entry for an emoji or for one of its skin-tone variants.
    func entry(for emoji: String) -> Entry? {
        allEntries.first { $0.emoji == emoji || $0.skinTones.contains(emoji) }
    }

    private var allEntries: [Entry] { groups.flatMap(\.entries) }

    private static func bundledText() -> String? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "emoji-catalog", withExtension: "tsv") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Whether this OS's emoji font draws an emoji as one glyph. An emoji from
/// a newer Unicode version than the OS knows falls back to its pieces (a
/// ZWJ sequence) or to the last-resort font (a new code point).
enum EmojiRenderSupport {
    /// Every Apple OS this app runs on (iOS 16, macOS 26) draws emoji up to
    /// this version, so only newer ones are checked.
    static let alwaysSupportedVersion = 14.0

    static func canRender(_ entry: EmojiCatalog.Entry) -> Bool {
        entry.version <= alwaysSupportedVersion || canRender(entry.emoji)
    }

    static func canRender(_ emoji: String) -> Bool {
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 20, nil)
        let attributed = NSAttributedString(
            string: emoji,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1,
              CTRunGetGlyphCount(runs[0]) == 1 else { return false }
        let attributes = CTRunGetAttributes(runs[0]) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String] as CFTypeRef?,
              CFGetTypeID(value) == CTFontGetTypeID() else { return false }
        let runFont = value as! CTFont
        guard (CTFontCopyPostScriptName(runFont) as String) == "AppleColorEmoji" else { return false }
        var glyph = CGGlyph()
        CTRunGetGlyphs(runs[0], CFRange(location: 0, length: 1), &glyph)
        return glyph != 0
    }
}
