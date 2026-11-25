//
// GIFSource.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// One GIF a picker source offers.
struct GIFPickerItem: Identifiable, Hashable, Sendable {
    /// What the message holds when this GIF is sent: a link the chat's GIF
    /// renderer shows, so older apps still get a working link.
    let link: URL
    /// A small rendition for the picker's grid; the link itself when the
    /// source has none.
    let previewURL: URL
    /// Width / height, when known.
    let aspectRatio: Double?
    /// A description for VoiceOver, when the source has one.
    let title: String?

    var id: String { link.absoluteString }
}

/// Where a source's next page starts. Only the source reads it.
struct GIFPageCursor: Hashable, Sendable {
    let value: String
}

struct GIFPage: Sendable {
    let items: [GIFPickerItem]
    /// Nil when there is nothing more.
    let next: GIFPageCursor?

    static let empty = GIFPage(items: [], next: nil)
}

/// A place the GIF picker finds GIFs. The picker shows one tab per source.
protocol GIFSource: Sendable {
    /// Stable identifier, also the tab's identity.
    var id: String { get }
    /// Whether `search` does anything. A source without search shows its
    /// browse list only.
    var supportsSearch: Bool { get }
    /// What the source shows with no search text.
    func browse(after cursor: GIFPageCursor?) async throws -> GIFPage
    func search(_ query: String, after cursor: GIFPageCursor?) async throws -> GIFPage
}

/// The GIFs I sent and the ones I received and loaded, from this device's
/// own list. No network: the media is already in the GIF cache.
struct RecentGIFSource: GIFSource {
    static let sourceID = "recent"

    let recents: GifRecentsStore

    init(recents: GifRecentsStore = .shared) {
        self.recents = recents
    }

    var id: String { Self.sourceID }
    var supportsSearch: Bool { false }

    func browse(after cursor: GIFPageCursor?) async throws -> GIFPage {
        guard cursor == nil else { return .empty }
        let items = recents.entries.compactMap { entry -> GIFPickerItem? in
            // Only links the renderer still accepts: the list may predate
            // a change to the allowlist.
            guard let url = URL(string: entry.link), GifLinkParser.parse(url) != nil else { return nil }
            return GIFPickerItem(link: url, previewURL: url, aspectRatio: entry.aspectRatio, title: nil)
        }
        return GIFPage(items: items, next: nil)
    }

    func search(_ query: String, after cursor: GIFPageCursor?) async throws -> GIFPage {
        .empty
    }
}
