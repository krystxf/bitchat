//
// ChatImageCacheTests.swift
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

@Suite("ChatImageCache")
struct ChatImageCacheTests {
    /// Writes a solid PNG of the given pixel size to a fresh temp file.
    private func makePNG(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-image-cache-\(UUID().uuidString).png")
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func aspectRatioComesFromTheHeader() throws {
        let url = try makePNG(width: 300, height: 100)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ChatImageCache.aspectRatio(for: url) == 3)
    }

    @Test func missingFileHasNoAspectRatio() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).png")
        #expect(ChatImageCache.aspectRatio(for: url) == nil)
    }

    @Test func thumbnailsAreDownsampledAndCached() throws {
        let url = try makePNG(width: 2000, height: 1000)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = try #require(ChatImageCache.loadThumbnail(for: url))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= CGFloat(ChatImageCache.thumbnailMaxPixelSize))
        // A row that scrolls back in finds the same thumbnail without decoding.
        #expect(ChatImageCache.cachedThumbnail(for: url) === thumbnail)
    }
}
