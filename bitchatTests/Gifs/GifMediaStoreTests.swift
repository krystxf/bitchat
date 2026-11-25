//
// GifMediaStoreTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import bitchat

/// An animated GIF of solid frames, written with ImageIO.
func makeAnimatedGIF(width: Int, height: Int, frames: Int, delay: Double) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames, nil)
    )
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
    for index in 0..<frames {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let shade = CGFloat(index) / CGFloat(max(1, frames - 1))
        context.setFillColor(CGColor(red: shade, green: 0.4, blue: 1 - shade, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Suite("GIF frame decoder")
struct GifFrameDecoderTests {
    @Test func smallGifsDecodeEveryFrameAtFullSize() {
        let plan = GifFrameDecoder.plan(frameCount: 30, width: 480, height: 270)
        #expect(plan == GifFrameDecoder.Plan(pixelSize: 480, stride: 1))
    }

    @Test func largeFramesAreDownsampled() {
        let plan = GifFrameDecoder.plan(frameCount: 10, width: 2000, height: 1000)
        #expect(plan?.pixelSize == GifFrameDecoder.maxPixelSize)
    }

    @Test(arguments: [(1_000, 500, 500), (240, 560, 560), (2_000, 4096, 4096), (600, 1920, 1080)])
    func longGifsStayWithinTheBudget(frameCount: Int, width: Int, height: Int) throws {
        let plan = try #require(GifFrameDecoder.plan(frameCount: frameCount, width: width, height: height))
        let kept = (frameCount + plan.stride - 1) / plan.stride
        let scale = min(1, Double(plan.pixelSize) / Double(max(width, height)))
        let frameBytes = Int((Double(width) * scale).rounded()) * Int((Double(height) * scale).rounded()) * 4
        #expect(kept <= GifFrameDecoder.maxFrames)
        #expect(kept * frameBytes <= GifFrameDecoder.maxDecodedBytes)
        #expect(plan.pixelSize >= GifFrameDecoder.minPixelSize)
    }

    @Test(arguments: [(0, 100, 100), (10, 0, 100), (GifFrameDecoder.maxSourceFrames + 1, 100, 100), (1, 5000, 5000)])
    func implausibleFilesAreRejected(frameCount: Int, width: Int, height: Int) {
        #expect(GifFrameDecoder.plan(frameCount: frameCount, width: width, height: height) == nil)
    }

    @Test func decodingKeepsFramesAndDelays() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-decode-\(UUID().uuidString).gif")
        try makeAnimatedGIF(width: 40, height: 20, frames: 3, delay: 0.05).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let frames = try #require(GifFrameDecoder.decode(url: url))

        #expect(frames.images.count == 3)
        #expect(frames.pixelSize == CGSize(width: 40, height: 20))
        #expect(frames.delays.allSatisfy { abs($0 - 0.05) < 0.001 })
        #expect(frames.images.first?.width == 40)
    }

    @Test func tooShortDelaysPlayAtATenthOfASecond() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-delay-\(UUID().uuidString).gif")
        try makeAnimatedGIF(width: 10, height: 10, frames: 2, delay: 0).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let frames = try #require(GifFrameDecoder.decode(url: url))
        #expect(frames.delays == [0.1, 0.1])
    }
}

/// Holds its one response until `open()`, and reports when a request
/// arrives, so a test can act while a load is in flight without sleeping.
final class GatedGifFetcher: GifHTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let response: GifHTTPResponse
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var count = 0
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init(response: GifHTTPResponse) {
        self.response = response
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
    }

    var requestCount: Int { lock.withLock { count } }

    func open() {
        let resumed = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiting.removeAll() }
            return waiting
        }
        resumed.forEach { $0.resume() }
    }

    func fetch(_ url: URL, maxBytes: Int, stopMarker: Data?) async throws -> GifHTTPResponse {
        lock.withLock { count += 1 }
        startedContinuation.yield()
        await withCheckedContinuation { continuation in
            let proceed = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiting.append(continuation)
                return false
            }
            if proceed { continuation.resume() }
        }
        return response
    }
}

@Suite("GIF media store")
struct GifMediaStoreTests {
    /// A Tenor GIF link: its MP4 rendition is tried first, then the GIF.
    static let link = URL(string: "https://media.tenor.com/3w0Our6WmXUAAAAC/brick.gif").flatMap(GifLinkParser.parse)!
    static let mp4URL = "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4"
    static let gifURL = "https://media.tenor.com/3w0Our6WmXUAAAAC/brick.gif"

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-store-\(UUID().uuidString)", isDirectory: true)
    }

    private func fetcherServingGIF() throws -> FakeGifFetcher {
        let fetcher = FakeGifFetcher()
        fetcher.respond(Self.mp4URL, status: 404)
        fetcher.respond(Self.gifURL, mimeType: "image/gif", body: try makeAnimatedGIF(width: 60, height: 30, frames: 2, delay: 0.1))
        return fetcher
    }

    @Test func aLoadWritesTheFileAndItsRecord() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: try fetcherServingGIF()))

        let asset = try await store.load(Self.link)

        #expect(asset.format == .gif)
        #expect(asset.aspectRatio == 2)
        #expect(asset.fileURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: asset.fileURL.path))
        // The file is named by a hash, not by the link.
        #expect(!asset.fileURL.lastPathComponent.contains("brick"))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(store.cachedAsset(for: Self.link) == asset)
    }

    @Test func aNewStoreFindsTheCachedFileWithoutNetwork() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: try fetcherServingGIF()))
        let asset = try await first.load(Self.link)

        let offline = FakeGifFetcher()
        let second = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: offline))

        #expect(second.cachedAsset(for: Self.link) == asset)
        #expect(try await second.load(Self.link) == asset)
        #expect(second.asset(forFileURL: asset.fileURL) == asset)
        #expect(offline.requests.isEmpty)
    }

    @Test func filesOutsideTheCacheAreNotAssets() throws {
        let store = GifMediaStore(directory: makeDirectory(), resolver: GifResolver(fetcher: FakeGifFetcher()))
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("elsewhere.gif")
        #expect(store.asset(forFileURL: outside) == nil)
    }

    @Test func concurrentLoadsShareOneDownload() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = try #require(URL(string: "https://giphy.com/stickers/hi-l41lUJ1YoZB1lHVPG").flatMap(GifLinkParser.parse))
        let fetcher = GatedGifFetcher(response: GifHTTPResponse(
            url: URL(string: "https://media.giphy.com/media/l41lUJ1YoZB1lHVPG/giphy.webp")!,
            statusCode: 200,
            mimeType: "image/gif",
            location: nil,
            body: try makeAnimatedGIF(width: 20, height: 20, frames: 2, delay: 0.1)
        ))
        let store = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: fetcher))

        let first = Task { try await store.load(link) }
        var started = fetcher.started.makeAsyncIterator()
        _ = await started.next()
        let second = Task { try await store.load(link) }
        fetcher.open()

        // The WebP candidate answers with GIF bytes, so it is rejected and
        // the GIF candidate loads: two requests in total, not four.
        let assets = try await [first.value, second.value]
        #expect(assets[0] == assets[1])
        #expect(fetcher.requestCount == 2)
    }

    @Test func removeAllDeletesTheFolderAndForgetsReveals() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: try fetcherServingGIF()))
        _ = try await store.load(Self.link)
        store.markRevealed(messageID: "m1")
        #expect(store.isRevealed(messageID: "m1"))

        store.removeAll()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(store.cachedAsset(for: Self.link) == nil)
        #expect(!store.isRevealed(messageID: "m1"))
    }

    @Test func aLoadInFlightDuringAWipeLeavesNothing() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = try #require(URL(string: "https://media.tenor.com/3w0Our6WmXUAAAAC/brick.gif").flatMap(GifLinkParser.parse))
        let fetcher = GatedGifFetcher(response: GifHTTPResponse(
            url: URL(string: Self.mp4URL)!,
            statusCode: 200,
            mimeType: "image/gif",
            location: nil,
            body: try makeAnimatedGIF(width: 20, height: 20, frames: 2, delay: 0.1)
        ))
        let store = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: fetcher))

        let load = Task { try await store.load(link) }
        var started = fetcher.started.makeAsyncIterator()
        _ = await started.next()
        store.removeAll()
        fetcher.open()

        await #expect(throws: (any Error).self) { _ = try await load.value }
        #expect(store.cachedAsset(for: link) == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func undecodableMediaIsNotKept() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = FakeGifFetcher()
        fetcher.respond(Self.mp4URL, status: 404)
        // The right magic bytes, then nothing ImageIO can read.
        fetcher.respond(Self.gifURL, mimeType: "image/gif", body: Data("GIF89a".utf8) + Data(repeating: 0xFF, count: 64))
        let store = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: fetcher))

        await #expect(throws: GifLoadError.undecodable) { _ = try await store.load(Self.link) }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(leftovers.isEmpty)
    }
}
