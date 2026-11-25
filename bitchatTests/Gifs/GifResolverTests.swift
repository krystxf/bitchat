//
// GifResolverTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation
import Testing
@testable import bitchat

/// Canned responses by URL, recording every request. A request for a URL
/// with no canned response fails the test.
final class FakeGifFetcher: GifHTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: GifHTTPResponse] = [:]
    private var errors: [String: Error] = [:]
    private var requested: [String] = []

    var requests: [String] { lock.withLock { requested } }

    func respond(_ url: String, status: Int = 200, mimeType: String? = nil, location: String? = nil, body: Data = Data()) {
        lock.withLock {
            responses[url] = GifHTTPResponse(
                url: URL(string: url)!,
                statusCode: status,
                mimeType: mimeType,
                location: location,
                body: body
            )
        }
    }

    func fail(_ url: String, with error: Error) {
        lock.withLock { errors[url] = error }
    }

    func fetch(_ url: URL, maxBytes: Int, stopMarker: Data?) async throws -> GifHTTPResponse {
        let key = url.absoluteString
        let (response, error) = lock.withLock { () -> (GifHTTPResponse?, Error?) in
            requested.append(key)
            return (responses[key], errors[key])
        }
        if let error { throw error }
        guard let response else {
            Issue.record("unexpected request: \(key)")
            throw GifLoadError.badStatus(404)
        }
        if response.body.count > maxBytes { throw GifLoadError.tooLarge }
        return response
    }
}

@Suite("GIF resolver")
struct GifResolverTests {
    static let mp4Bytes = Data([0, 0, 0, 0x18]) + Data("ftypmp42".utf8) + Data(count: 20)
    static let gifBytes = Data("GIF89a".utf8) + Data(count: 20)

    private func link(_ string: String) throws -> GifLink {
        try #require(URL(string: string).flatMap(GifLinkParser.parse))
    }

    @Test func giphyLinksResolveWithoutAPageFetch() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.respond("https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.mp4", mimeType: "video/mp4", body: Self.mp4Bytes)
        let resolver = GifResolver(fetcher: fetcher)

        let media = try await resolver.media(for: link("https://giphy.com/gifs/office-3o7btPCcdNniyf0ArS"))

        #expect(media.format == .mp4)
        #expect(media.data == Self.mp4Bytes)
        #expect(fetcher.requests == ["https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.mp4"])
    }

    @Test func aMissingMP4FallsBackToTheGIF() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.respond("https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.mp4", status: 404)
        fetcher.respond("https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif", mimeType: "image/gif", body: Self.gifBytes)

        let media = try await GifResolver(fetcher: fetcher).media(for: link("https://i.giphy.com/3o7btPCcdNniyf0ArS.gif"))

        #expect(media.format == .gif)
    }

    @Test func giphyShortLinksFollowOneCheckedRedirect() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.respond("https://gph.is/g/E00kL5p", status: 301, location: "https://giphy.com/gifs/matt-mcdm-colville-McPHZWaKkFImC6ODE5")
        let candidates = try await GifResolver(fetcher: fetcher).candidates(for: link("https://gph.is/g/E00kL5p"))

        #expect(candidates.first?.url.absoluteString == "https://media.giphy.com/media/McPHZWaKkFImC6ODE5/giphy.mp4")
        // The Giphy page itself is never fetched: its ID names the media.
        #expect(fetcher.requests == ["https://gph.is/g/E00kL5p"])
    }

    @Test func tenorShortLinksFollowRedirectsToThePage() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.respond("https://tenor.com/bEb8s.gif", status: 301, location: "https://tenor.com/beb8s.gif")
        fetcher.respond("https://tenor.com/beb8s.gif", status: 301, location: "/view/brick-gif-16072518840379414901")
        fetcher.respond(
            "https://tenor.com/view/brick-gif-16072518840379414901",
            mimeType: "text/html",
            body: Data(GifMediaSourceTests.tenorHead.utf8)
        )
        fetcher.respond("https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4", mimeType: "video/mp4", body: Self.mp4Bytes)

        let media = try await GifResolver(fetcher: fetcher).media(for: link("https://tenor.com/bEb8s.gif"))

        #expect(media.format == .mp4)
        #expect(media.pixelSize == CGSize(width: 498, height: 494))
        #expect(fetcher.requests.count == 4)
    }

    @Test func aRedirectOffTheAllowlistIsNotFollowed() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.respond("https://gph.is/2QRsryK", status: 302, location: "https://tracker.example/gif")

        await #expect(throws: GifLoadError.notAllowed) {
            _ = try await GifResolver(fetcher: fetcher).candidates(for: link("https://gph.is/2QRsryK"))
        }
        #expect(fetcher.requests == ["https://gph.is/2QRsryK"])
    }

    @Test func aMediaRedirectOffTheAllowlistIsNotFollowed() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.respond(
            "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4",
            status: 302,
            location: "http://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4"
        )

        await #expect(throws: GifLoadError.notAllowed) {
            _ = try await GifResolver(fetcher: fetcher).media(for: link("https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4"))
        }
    }

    @Test func endlessRedirectsStop() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.respond("https://gph.is/aaaaaa", status: 301, location: "https://gph.is/bbbbbb")
        fetcher.respond("https://gph.is/bbbbbb", status: 301, location: "https://gph.is/aaaaaa")

        await #expect(throws: GifLoadError.tooManyRedirects) {
            _ = try await GifResolver(fetcher: fetcher).candidates(for: link("https://gph.is/aaaaaa"))
        }
        #expect(fetcher.requests.count == GifResolver.maxRedirects + 1)
    }

    @Test func contentThatIsNotTheClaimedFormatIsRejected() async throws {
        let fetcher = FakeGifFetcher()
        let mp4 = "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4"
        // Labelled MP4, but the bytes are HTML.
        fetcher.respond(mp4, mimeType: "video/mp4", body: Data("<!doctype html><html></html>".utf8))

        await #expect(throws: GifLoadError.unexpectedContent) {
            _ = try await GifResolver(fetcher: fetcher).media(for: link(mp4))
        }
    }

    @Test func aWrongContentTypeIsRejected() async throws {
        let fetcher = FakeGifFetcher()
        let mp4 = "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4"
        fetcher.respond(mp4, mimeType: "text/html", body: Self.mp4Bytes)

        await #expect(throws: GifLoadError.unexpectedContent) {
            _ = try await GifResolver(fetcher: fetcher).media(for: link(mp4))
        }
    }

    @Test func aTenorPageWithoutMediaFails() async throws {
        let fetcher = FakeGifFetcher()
        let page = "https://tenor.com/view/brick-gif-16072518840379414901"
        fetcher.respond(page, mimeType: "text/html", body: Data("<html><head></head></html>".utf8))

        await #expect(throws: GifLoadError.noMedia) {
            _ = try await GifResolver(fetcher: fetcher).media(for: link(page))
        }
    }

    @Test func torUnavailableStopsAtTheFirstRequest() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.fail("https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.mp4", with: GifLoadError.torUnavailable)

        await #expect(throws: GifLoadError.torUnavailable) {
            _ = try await GifResolver(fetcher: fetcher).media(for: link("https://giphy.com/gifs/3o7btPCcdNniyf0ArS"))
        }
        // The GIF fallback is not tried: it would meet the same closed route.
        #expect(fetcher.requests.count == 1)
    }

    @Test func oversizedMediaFallsBackToTheNextRendition() async throws {
        let fetcher = FakeGifFetcher()
        fetcher.fail("https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.mp4", with: GifLoadError.tooLarge)
        fetcher.respond("https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif", mimeType: "image/gif", body: Self.gifBytes)

        let media = try await GifResolver(fetcher: fetcher).media(for: link("https://giphy.com/gifs/3o7btPCcdNniyf0ArS"))
        #expect(media.format == .gif)
    }
}
