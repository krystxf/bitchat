//
// GifPickerModelTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

/// Pages by request, recording each one.
final class FakeGIFSource: GIFSource, @unchecked Sendable {
    let id: String
    let supportsSearch: Bool
    private let lock = NSLock()
    private var pages: [String: Result<GIFPage, Error>] = [:]
    private var requests: [String] = []

    init(id: String, supportsSearch: Bool) {
        self.id = id
        self.supportsSearch = supportsSearch
    }

    var requested: [String] { lock.withLock { requests } }

    /// `query` nil is browsing; `cursor` nil is the first page.
    func set(query: String?, cursor: String?, _ result: Result<GIFPage, Error>) {
        lock.withLock { pages[Self.key(query, cursor)] = result }
    }

    func browse(after cursor: GIFPageCursor?) async throws -> GIFPage {
        try answer(Self.key(nil, cursor?.value))
    }

    func search(_ query: String, after cursor: GIFPageCursor?) async throws -> GIFPage {
        try answer(Self.key(query, cursor?.value))
    }

    private func answer(_ key: String) throws -> GIFPage {
        let result = lock.withLock { () -> Result<GIFPage, Error>? in
            requests.append(key)
            return pages[key]
        }
        return try (result ?? .success(.empty)).get()
    }

    private static func key(_ query: String?, _ cursor: String?) -> String {
        "\(query ?? "<browse>")@\(cursor ?? "start")"
    }
}

@MainActor
@Suite("GIF picker model")
struct GifPickerModelTests {
    private func item(_ name: String) -> GIFPickerItem {
        let url = URL(string: "https://image.nostr.build/\(name).gif")!
        return GIFPickerItem(link: url, previewURL: url, aspectRatio: 1.5, title: name)
    }

    private func makeRecents() throws -> (GifRecentsStore, () -> Void) {
        let suite = "GifPickerModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (GifRecentsStore(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func opensOnSearchWhenNothingIsRecent() throws {
        let (recents, cleanup) = try makeRecents()
        defer { cleanup() }
        let model = GifPickerModel(
            sources: [RecentGIFSource(recents: recents), FakeGIFSource(id: "nostr", supportsSearch: true)],
            recents: recents,
            sendLink: { _ in }
        )
        #expect(model.selectedSourceID == "nostr")
    }

    @Test func opensOnRecentWhenItHasGifs() throws {
        let (recents, cleanup) = try makeRecents()
        defer { cleanup() }
        recents.record(link: "https://giphy.com/gifs/3o7btPCcdNniyf0ArS", aspectRatio: nil, date: Date())
        let model = GifPickerModel(
            sources: [RecentGIFSource(recents: recents), FakeGIFSource(id: "nostr", supportsSearch: true)],
            recents: recents,
            sendLink: { _ in }
        )
        #expect(model.selectedSourceID == RecentGIFSource.sourceID)
    }

    @Test func typingOnRecentMovesToSearch() throws {
        let (recents, cleanup) = try makeRecents()
        defer { cleanup() }
        recents.record(link: "https://giphy.com/gifs/3o7btPCcdNniyf0ArS", aspectRatio: nil, date: Date())
        let model = GifPickerModel(
            sources: [RecentGIFSource(recents: recents), FakeGIFSource(id: "nostr", supportsSearch: true)],
            recents: recents,
            sendLink: { _ in }
        )

        model.query = "  "
        #expect(model.selectedSourceID == RecentGIFSource.sourceID)
        model.query = "cat"
        #expect(model.selectedSourceID == "nostr")
        #expect(model.activeQuery == "cat")
        #expect(model.requestKey == "nostr|cat")
    }

    @Test func firstPageLoadsThenEmptyAndFailureStates() async throws {
        let (recents, cleanup) = try makeRecents()
        defer { cleanup() }
        let source = FakeGIFSource(id: "nostr", supportsSearch: true)
        source.set(query: nil, cursor: nil, .success(GIFPage(items: [item("a1b2c3d4"), item("a1b2c3d4"), item("e5f6a7b8")], next: nil)))
        source.set(query: "none", cursor: nil, .success(.empty))
        source.set(query: "down", cursor: nil, .failure(URLError(.notConnectedToInternet)))
        source.set(query: "tor", cursor: nil, .failure(GifLoadError.torUnavailable))
        let model = GifPickerModel(sources: [source], recents: recents, sendLink: { _ in })

        await model.reload()
        #expect(model.phase == .loaded)
        #expect(model.items.map(\.title) == ["a1b2c3d4", "e5f6a7b8"])

        model.query = "none"
        await model.reload()
        #expect(model.phase == .empty)
        #expect(model.items.isEmpty)

        model.query = "down"
        await model.reload()
        #expect(model.phase == .failed(torUnavailable: false))

        model.query = "tor"
        await model.reload()
        #expect(model.phase == .failed(torUnavailable: true))
    }

    @Test func pagingAppendsNewItemsAndStopsWhenNothingIsNew() async throws {
        let (recents, cleanup) = try makeRecents()
        defer { cleanup() }
        let source = FakeGIFSource(id: "nostr", supportsSearch: true)
        let first = (0..<8).map { item("first\($0)aa") }
        source.set(query: "cat", cursor: nil, .success(GIFPage(items: first, next: GIFPageCursor(value: "p2"))))
        source.set(query: "cat", cursor: "p2", .success(GIFPage(items: [first[7], item("second0a")], next: GIFPageCursor(value: "p3"))))
        source.set(query: "cat", cursor: "p3", .success(GIFPage(items: [item("second0a")], next: GIFPageCursor(value: "p4"))))
        let model = GifPickerModel(sources: [source], recents: recents, sendLink: { _ in })
        model.query = "cat"
        await model.reload()

        // An item far from the end does not page.
        await model.loadMoreIfNeeded(currentItem: first[0])
        #expect(source.requested == ["cat@start"])

        await model.loadMoreIfNeeded(currentItem: first[7])
        #expect(model.items.count == 9)
        #expect(model.items.last?.title == "second0a")

        // Page three brings nothing new, which ends paging.
        await model.loadMoreIfNeeded(currentItem: model.items[8])
        await model.loadMoreIfNeeded(currentItem: model.items[8])
        #expect(source.requested == ["cat@start", "cat@p2", "cat@p3"])
        #expect(model.items.count == 9)
        #expect(!model.isLoadingMore)
    }

    @Test func sendingSendsTheLinkAndPutsItInRecent() throws {
        let (recents, cleanup) = try makeRecents()
        defer { cleanup() }
        var sent: [String] = []
        let model = GifPickerModel(
            sources: [FakeGIFSource(id: "nostr", supportsSearch: true)],
            recents: recents,
            sendLink: { sent.append($0) }
        )
        let gif = item("0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd")

        model.send(gif)

        // The message is the media link itself, which the GIF renderer shows.
        #expect(sent == ["https://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif"])
        #expect(sent.first.flatMap(GifMessageDetector.detect(in:))?.isLinkOnly == true)
        #expect(recents.entries.first?.link == sent.first)
        #expect(recents.entries.first?.aspectRatio == 1.5)
    }

    @Test func recentItemsSendTheLinkTheyWereSeenWith() async throws {
        let (recents, cleanup) = try makeRecents()
        defer { cleanup() }
        let link = "https://tenor.com/view/brick-gif-16072518840379414901"
        recents.record(link: link, aspectRatio: 1, date: Date())
        var sent: [String] = []
        let model = GifPickerModel(sources: [RecentGIFSource(recents: recents)], recents: recents, sendLink: { sent.append($0) })

        await model.reload()
        let recent = try #require(model.items.first)
        model.send(recent)

        #expect(sent == [link])
    }
}
