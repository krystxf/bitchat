//
// GifFrameDecoder.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation
import ImageIO

/// The decoded frames of an animated GIF or WebP, ready to play.
final class GifFrames {
    let images: [CGImage]
    /// Seconds each image shows.
    let delays: [Double]
    let pixelSize: CGSize

    var duration: Double { delays.reduce(0, +) }

    /// Decoded bytes, the cost the frame cache counts.
    var byteCount: Int {
        images.reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }

    init(images: [CGImage], delays: [Double], pixelSize: CGSize) {
        self.images = images
        self.delays = delays
        self.pixelSize = pixelSize
    }
}

/// How large and how many frames a decode may produce.
struct GifDecodeProfile: Hashable, Sendable {
    /// Longest side of a decoded frame.
    let maxPixelSize: Int
    /// Frames are never shrunk below this side to fit the budget; frames
    /// are skipped instead.
    let minPixelSize: Int
    let maxFrames: Int
    let maxDecodedBytes: Int

    /// A GIF in a chat bubble.
    static let message = GifDecodeProfile(
        maxPixelSize: GifFrameDecoder.maxPixelSize,
        minPixelSize: GifFrameDecoder.minPixelSize,
        maxFrames: GifFrameDecoder.maxFrames,
        maxDecodedBytes: GifFrameDecoder.maxDecodedBytes
    )

    /// A cell in the GIF picker's grid: about 120 pt wide at 2x, and many
    /// on screen at once, so each gets a fraction of a bubble's budget.
    static let preview = GifDecodeProfile(
        maxPixelSize: 240,
        minPixelSize: 96,
        maxFrames: 60,
        maxDecodedBytes: 4 * 1_048_576
    )
}

/// Decodes GIF and WebP frames through ImageIO, downsampled and within a
/// memory budget: a GIF can hold hundreds of frames, and decoding each at
/// full size would cost hundreds of megabytes for one chat row.
enum GifFrameDecoder {
    /// Longest side of a decoded frame: the 280 pt bubble at 2x. GIF
    /// services rarely serve larger.
    static let maxPixelSize = 560
    /// Frames are never shrunk below this side to fit the budget; frames are
    /// skipped instead.
    static let minPixelSize = 160
    static let maxFrames = 240
    static let maxDecodedBytes = 32 * 1_048_576
    /// Files claiming more are rejected, not decoded.
    static let maxSourceFrames = 2_000
    static let maxSourcePixelArea = 4096 * 4096

    struct Plan: Equatable {
        /// Longest side each frame decodes to.
        let pixelSize: Int
        /// Every `stride`-th frame is kept; the skipped frames' time is
        /// added to the frame kept before them.
        let stride: Int
    }

    /// How to decode `frameCount` frames of `width` x `height` within the
    /// profile's limits. Nil when the file claims more than any GIF should.
    static func plan(frameCount: Int, width: Int, height: Int, profile: GifDecodeProfile = .message) -> Plan? {
        guard frameCount > 0, width > 0, height > 0,
              frameCount <= maxSourceFrames,
              width * height <= maxSourcePixelArea
        else { return nil }
        let longest = max(width, height)
        var stride = max(1, Int((Double(frameCount) / Double(profile.maxFrames)).rounded(.up)))
        var kept = keptFrames(frameCount, stride: stride)
        var pixelSize = min(profile.maxPixelSize, longest)
        if kept * bytes(width: width, height: height, pixelSize: pixelSize) > profile.maxDecodedBytes {
            // The pixel count a frame may have, then the side that gives it.
            let perFrame = Double(profile.maxDecodedBytes) / Double(kept * 4)
            let scale = (perFrame / Double(width * height)).squareRoot()
            pixelSize = min(pixelSize, max(min(profile.minPixelSize, longest), Int(Double(longest) * scale)))
        }
        while kept > 1, kept * bytes(width: width, height: height, pixelSize: pixelSize) > profile.maxDecodedBytes {
            stride += 1
            kept = keptFrames(frameCount, stride: stride)
        }
        return Plan(pixelSize: pixelSize, stride: stride)
    }

    /// Width and height of the first frame, read from the header.
    static func pixelSize(of data: Data) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return pixelSize(of: source)
    }

    /// Decodes the frames. Call it off the main thread.
    static func decode(url: URL, profile: GifDecodeProfile = .message) -> GifFrames? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let size = pixelSize(of: source),
              let plan = plan(
                frameCount: CGImageSourceGetCount(source),
                width: Int(size.width),
                height: Int(size.height),
                profile: profile
              )
        else { return nil }
        let count = CGImageSourceGetCount(source)
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: plan.pixelSize
        ] as CFDictionary
        var images: [CGImage] = []
        var delays: [Double] = []
        images.reserveCapacity(keptFrames(count, stride: plan.stride))
        for index in Swift.stride(from: 0, to: count, by: plan.stride) {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions) else { continue }
            images.append(image)
            let skipped = index..<min(index + plan.stride, count)
            delays.append(skipped.reduce(0) { $0 + frameDelay(source, at: $1) })
        }
        guard !images.isEmpty else { return nil }
        return GifFrames(images: images, delays: delays, pixelSize: size)
    }

    /// A frame's delay. Browsers show delays under 20 ms as 100 ms, and
    /// GIFs are authored for that, so this does the same.
    static func frameDelay(_ source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        let delay: Double?
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        } else if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            delay = (webp[kCGImagePropertyWebPUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (webp[kCGImagePropertyWebPDelayTime] as? NSNumber)?.doubleValue
        } else {
            delay = nil
        }
        guard let delay, delay >= 0.02 else { return 0.1 }
        return delay
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func keptFrames(_ count: Int, stride: Int) -> Int {
        (count + stride - 1) / stride
    }

    /// Decoded bytes of one frame scaled so its longest side is `pixelSize`.
    private static func bytes(width: Int, height: Int, pixelSize: Int) -> Int {
        let scale = min(1, Double(pixelSize) / Double(max(width, height)))
        let scaledWidth = max(1, Int((Double(width) * scale).rounded()))
        let scaledHeight = max(1, Int((Double(height) * scale).rounded()))
        return scaledWidth * scaledHeight * 4
    }
}

/// Decoded frames kept in memory, so a row that scrolls back in plays at
/// once. Bounded by decoded bytes; the system may also evict under memory
/// pressure.
enum GifFrameCache {
    private static let cache: NSCache<NSString, GifFrames> = {
        let cache = NSCache<NSString, GifFrames>()
        cache.totalCostLimit = 96 * 1_048_576
        return cache
    }()

    /// One file decodes differently per profile, so both form the key.
    private static func key(_ url: URL, _ profile: GifDecodeProfile) -> NSString {
        "\(profile.maxPixelSize)/\(profile.maxDecodedBytes)|\(url.absoluteString)" as NSString
    }

    static func cachedFrames(for url: URL, profile: GifDecodeProfile = .message) -> GifFrames? {
        cache.object(forKey: key(url, profile))
    }

    /// Decodes and caches. Call it off the main thread.
    static func loadFrames(for url: URL, profile: GifDecodeProfile = .message) -> GifFrames? {
        if let cached = cachedFrames(for: url, profile: profile) { return cached }
        guard let frames = GifFrameDecoder.decode(url: url, profile: profile) else { return nil }
        cache.setObject(frames, forKey: key(url, profile), cost: frames.byteCount)
        return frames
    }

    static func removeAll() {
        cache.removeAllObjects()
    }
}
