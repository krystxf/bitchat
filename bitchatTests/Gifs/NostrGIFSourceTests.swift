//
// NostrGIFSourceTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

/// Canned events per relay, recording every filter it was sent.
final class FakeRelayQuery: NostrRelayQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [URL: Result<[NostrEvent], Error>] = [:]
    private var sent: [(URL, NostrGIFFilter)] = []

    var filters: [NostrGIFFilter] { lock.withLock { sent.map(\.1) } }

    func answer(_ relay: URL, with events: [NostrEvent]) {
        lock.withLock { answers[relay] = .success(events) }
    }

    func fail(_ relay: URL, with error: Error) {
        lock.withLock { answers[relay] = .failure(error) }
    }

    func events(from relay: URL, filter: NostrGIFFilter) async throws -> [NostrEvent] {
        let answer = lock.withLock { () -> Result<[NostrEvent], Error>? in
            sent.append((relay, filter))
            return answers[relay]
        }
        return try (answer ?? .success([])).get()
    }
}

@Suite("Nostr GIF search")
struct NostrGIFSourceTests {
    private struct Fixture: Decodable {
        let subscriptionID: String
        let frames: [String]
    }

    /// Frames wss://nostr.wine sent for "thumbs up" (see the fixture's note).
    private func fixture() throws -> Fixture {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: MockKeychain.self)
        #endif
        let url = try #require(bundle.url(forResource: "Nip50GifSearchFrames", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func fixtureEvents() throws -> [NostrEvent] {
        let fixture = try fixture()
        return fixture.frames.compactMap { frame in
            if case .event(let event) = NostrRelayFrame.parse(frame, subscriptionID: fixture.subscriptionID) {
                return event
            }
            return nil
        }
    }

    private func event(
        kind: Int = 1063,
        createdAt: Int = 100,
        tags: [[String]],
        content: String = ""
    ) throws -> NostrEvent {
        try NostrEvent(from: [
            "id": UUID().uuidString,
            "pubkey": String(repeating: "a", count: 64),
            "created_at": createdAt,
            "kind": kind,
            "tags": tags,
            "content": content
        ])
    }

    private func gifEvent(_ file: String, createdAt: Int = 100) throws -> NostrEvent {
        try event(createdAt: createdAt, tags: [
            ["url", "https://image.nostr.build/\(file).gif"],
            ["m", "image/gif"],
            ["dim", "200x100"]
        ])
    }

    static let relayA = URL(string: "wss://relay-a.example")!
    static let relayB = URL(string: "wss://relay-b.example")!

    // MARK: Requests

    @Test func searchRequestsAreNIP50FiltersForGifFileEvents() {
        let filter = NostrGIFFilter(search: "thumbs up", tag: nil, until: nil, limit: 30)
        #expect(filter.requestFrame(subscriptionID: "gif-1")
            == ##"["REQ","gif-1",{"#m":["image/gif"],"kinds":[1063],"limit":30,"search":"thumbs up"}]"##)
    }

    @Test func browseRequestsAskForTheTaggedUploads() {
        let filter = NostrGIFFilter(search: nil, tag: "gifbuddy", until: 1_700_000_000, limit: 30)
        #expect(filter.requestFrame(subscriptionID: "gif-2")
            == ##"["REQ","gif-2",{"#m":["image/gif"],"#t":["gifbuddy"],"kinds":[1063],"limit":30,"until":1700000000}]"##)
        #expect(NostrGIFFilter.closeFrame(subscriptionID: "gif-2") == #"["CLOSE","gif-2"]"#)
    }

    @Test func searchTextIsTrimmedAndBounded() {
        #expect(NostrGIFFilter.searchText("  thumbs \n  up ") == "thumbs up")
        #expect(NostrGIFFilter.searchText("   ") == nil)
        #expect(NostrGIFFilter.searchText(String(repeating: "a", count: 500))?.count == NostrGIFFilter.maxSearchLength)
    }

    // MARK: Decoding

    @Test func fixtureFramesDecodeToEventsAndTheEnd() throws {
        let fixture = try fixture()
        let frames = fixture.frames.map { NostrRelayFrame.parse($0, subscriptionID: fixture.subscriptionID) }
        let events = frames.compactMap { frame -> NostrEvent? in
            if case .event(let event) = frame { return event }
            return nil
        }
        #expect(events.count == 4)
        #expect(events.allSatisfy { $0.kind == 1063 })
        guard case .endOfStoredEvents = frames.last else {
            Issue.record("the last frame is not EOSE")
            return
        }
    }

    @Test func fixtureEventsBecomeItemsWithPreviewSizeAndTitle() throws {
        let items = try fixtureEvents().compactMap(NostrGIFEvent.item(from:))
        #expect(items.count == 4)
        let first = try #require(items.first)
        #expect(first.link.absoluteString
            == "https://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif")
        // nostr.build's small thumbnail, not the Tenor still after it.
        #expect(first.previewURL.absoluteString
            == "https://image.nostr.build/thumb/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif")
        #expect(first.aspectRatio == 360.0 / 270.0)
        #expect(first.title?.hasPrefix("a young boy in a blue shirt") == true)
        // Every link is one the chat's GIF renderer shows.
        #expect(items.allSatisfy { GifLinkParser.parse($0.link)?.provider == .nostrBuild })
    }

    @Test func framesForOtherSubscriptionsAndOtherMessagesAreSorted() {
        #expect({
            if case .ignored = NostrRelayFrame.parse(#"["EOSE","someone-else"]"#, subscriptionID: "gif-1") { return true }
            return false
        }())
        #expect({
            if case .notice("slow down") = NostrRelayFrame.parse(#"["NOTICE","slow down"]"#, subscriptionID: "gif-1") { return true }
            return false
        }())
        #expect({
            if case .closed(reason: "auth-required: please authenticate") = NostrRelayFrame.parse(
                #"["CLOSED","gif-1","auth-required: please authenticate"]"#, subscriptionID: "gif-1"
            ) { return true }
            return false
        }())
        #expect({
            if case .ignored = NostrRelayFrame.parse("not json", subscriptionID: "gif-1") { return true }
            return false
        }())
        #expect({
            if case .ignored = NostrRelayFrame.parse(#"["EVENT","gif-1",{"kind":1063}]"#, subscriptionID: "gif-1") { return true }
            return false
        }())
    }

    @Test func eventsTheRendererWouldNotShowAreDropped() throws {
        // A video, not a GIF.
        #expect(NostrGIFEvent.item(from: try event(tags: [
            ["url", "https://video.nostr.build/abcdef123456.mp4"], ["m", "video/mp4"]
        ])) == nil)
        // A GIF on a host off the allowlist.
        #expect(NostrGIFEvent.item(from: try event(tags: [
            ["url", "https://gifdb.com/images/thumbnail/cat.gif"], ["m", "image/gif"]
        ])) == nil)
        // Not HTTPS.
        #expect(NostrGIFEvent.item(from: try event(tags: [
            ["url", "http://image.nostr.build/abcdef123456.gif"], ["m", "image/gif"]
        ])) == nil)
        // Another kind.
        #expect(NostrGIFEvent.item(from: try event(kind: 1, tags: [
            ["url", "https://image.nostr.build/abcdef123456.gif"], ["m", "image/gif"]
        ])) == nil)
    }

    @Test func tenorMediaLinksCountAndPreviewFallsBackToTheLink() throws {
        let item = try #require(NostrGIFEvent.item(from: try event(tags: [
            ["url", "https://media.tenor.com/3w0Our6WmXUAAAAC/brick.gif"],
            ["m", "image/gif"],
            ["thumb", "https://evil.example/thumb.gif"]
        ], content: "Brick\nmore")))
        #expect(item.previewURL == item.link)
        #expect(item.title == "Brick")
        #expect(item.aspectRatio == nil)
    }

    @Test func dimensionsGiveTheShape() {
        #expect(NostrGIFEvent.aspectRatio(fromDimensions: "498x328") == 498.0 / 328.0)
        #expect(NostrGIFEvent.aspectRatio(fromDimensions: "0x10") == nil)
        #expect(NostrGIFEvent.aspectRatio(fromDimensions: "wide") == nil)
    }

    // MARK: Source

    @Test func searchMergesRelaysInOrderOneItemPerLink() async throws {
        let client = FakeRelayQuery()
        client.answer(Self.relayA, with: [try gifEvent("aaaaaa1", createdAt: 300), try gifEvent("bbbbbb2", createdAt: 200)])
        client.answer(Self.relayB, with: [try gifEvent("bbbbbb2", createdAt: 250), try gifEvent("cccccc3", createdAt: 150)])
        let source = NostrGIFSource(relays: [Self.relayA, Self.relayB], client: client)

        let page = try await source.search("cat", after: nil)

        #expect(page.items.map(\.link.lastPathComponent) == ["aaaaaa1.gif", "bbbbbb2.gif", "cccccc3.gif"])
        #expect(page.next == GIFPageCursor(value: "149"))
        #expect(client.filters.allSatisfy { $0.search == "cat" && $0.until == nil && $0.tag == nil })
    }

    @Test func theNextPageAsksForOlderEvents() async throws {
        let client = FakeRelayQuery()
        let source = NostrGIFSource(relays: [Self.relayA], client: client)

        let page = try await source.search("cat", after: GIFPageCursor(value: "149"))

        #expect(client.filters.first?.until == 149)
        #expect(page.items.isEmpty)
        #expect(page.next == nil)
    }

    @Test func blankSearchBrowsesTheTaggedUploads() async throws {
        let client = FakeRelayQuery()
        let source = NostrGIFSource(relays: [Self.relayA], client: client)

        _ = try await source.search("   ", after: nil)

        #expect(client.filters == [NostrGIFFilter(search: nil, tag: NostrGIFSource.browseTag, until: nil, limit: NostrGIFSource.pageSize)])
    }

    @Test func oneFailingRelayDoesNotHideTheOther() async throws {
        let client = FakeRelayQuery()
        client.fail(Self.relayA, with: URLError(.timedOut))
        client.answer(Self.relayB, with: [try gifEvent("dddddd4")])
        let source = NostrGIFSource(relays: [Self.relayA, Self.relayB], client: client)

        let page = try await source.search("cat", after: nil)
        #expect(page.items.count == 1)
    }

    @Test func torBeingDownIsWhatTheErrorSays() async throws {
        let client = FakeRelayQuery()
        client.fail(Self.relayA, with: URLError(.cannotConnectToHost))
        client.fail(Self.relayB, with: GifLoadError.torUnavailable)
        let source = NostrGIFSource(relays: [Self.relayA, Self.relayB], client: client)

        await #expect(throws: GifLoadError.torUnavailable) {
            _ = try await source.search("cat", after: nil)
        }
    }

    @Test func recentListsMyGifsNewestFirstWithoutSearch() async throws {
        let suite = "NostrGIFSourceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recents = GifRecentsStore(defaults: defaults)
        recents.record(link: "https://giphy.com/gifs/3o7btPCcdNniyf0ArS", aspectRatio: 1.5, date: Date(timeIntervalSince1970: 1))
        recents.record(link: "https://example.com/not-a-gif.gif", aspectRatio: nil, date: Date(timeIntervalSince1970: 2))
        recents.record(link: "https://image.nostr.build/eeeeee5.gif", aspectRatio: 2, date: Date(timeIntervalSince1970: 3))
        let source = RecentGIFSource(recents: recents)

        let page = try await source.browse(after: nil)

        #expect(page.items.map(\.link.absoluteString) == [
            "https://image.nostr.build/eeeeee5.gif",
            "https://giphy.com/gifs/3o7btPCcdNniyf0ArS"
        ])
        #expect(page.items.first?.aspectRatio == 2)
        #expect(page.next == nil)
        #expect(!source.supportsSearch)
        #expect(try await source.search("cat", after: nil).items.isEmpty)
    }
}
