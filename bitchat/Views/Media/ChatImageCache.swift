//
// ChatImageCache.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation
import ImageIO
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Sizes and thumbnails for images in the chat timeline.
///
/// The timeline is a `LazyVStack`, which builds rows as they scroll in and
/// drops them again. An image row that laid out as a placeholder and only
/// learned its real height after decoding grew mid-scroll, so the content
/// shifted and the scroll indicator jumped. This cache answers the aspect
/// ratio from the file header (no decode) before the first layout, and keeps
/// downsampled thumbnails so a row that scrolls back in shows its image at
/// once.
enum ChatImageCache {
    /// Longest side of a timeline thumbnail, in pixels: the 280 pt maximum
    /// bubble width at 3x.
    static let thumbnailMaxPixelSize = 840

    private static let aspectRatios = NSCache<NSURL, NSNumber>()
    #if os(iOS)
    private static let thumbnails = NSCache<NSURL, UIImage>()
    #else
    private static let thumbnails = NSCache<NSURL, NSImage>()
    #endif

    /// Width / height as the image displays (EXIF orientation applied), read
    /// from the file header only. Nil when the file is missing or unreadable.
    static func aspectRatio(for url: URL) -> CGFloat? {
        if let cached = aspectRatios.object(forKey: url as NSURL) {
            return CGFloat(cached.doubleValue)
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else {
            return nil
        }
        // Orientations 5-8 rotate the image a quarter turn, so the stored
        // width and height swap on screen.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let ratio = orientation >= 5 ? height / width : width / height
        aspectRatios.setObject(NSNumber(value: ratio), forKey: url as NSURL)
        return CGFloat(ratio)
    }

    #if os(iOS)
    static func cachedThumbnail(for url: URL) -> UIImage? {
        thumbnails.object(forKey: url as NSURL)
    }

    /// Decodes a downsampled, orientation-corrected thumbnail. Call it off
    /// the main thread.
    static func loadThumbnail(for url: URL) -> UIImage? {
        if let cached = cachedThumbnail(for: url) { return cached }
        guard let cgImage = makeThumbnail(for: url) else { return nil }
        let image = UIImage(cgImage: cgImage)
        thumbnails.setObject(image, forKey: url as NSURL)
        return image
    }
    #else
    static func cachedThumbnail(for url: URL) -> NSImage? {
        thumbnails.object(forKey: url as NSURL)
    }

    /// Decodes a downsampled, orientation-corrected thumbnail. Call it off
    /// the main thread.
    static func loadThumbnail(for url: URL) -> NSImage? {
        if let cached = cachedThumbnail(for: url) { return cached }
        guard let cgImage = makeThumbnail(for: url) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnails.setObject(image, forKey: url as NSURL)
        return image
    }
    #endif

    private static func makeThumbnail(for url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
