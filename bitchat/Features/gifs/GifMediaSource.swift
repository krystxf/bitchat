//
// GifMediaSource.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation

/// The file formats the chat plays. MP4 plays through AVFoundation; GIF and
/// WebP decode through ImageIO.
enum GifMediaFormat: String, Codable, Sendable {
    case mp4
    case gif
    case webp

    var fileExtension: String { rawValue }

    var isVideo: Bool { self == .mp4 }

    init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "mp4": self = .mp4
        case "gif": self = .gif
        case "webp": self = .webp
        default: return nil
        }
    }

    /// The MIME types a server may label this format with.
    var acceptedMimeTypes: Set<String> {
        switch self {
        case .mp4: return ["video/mp4"]
        case .gif: return ["image/gif"]
        case .webp: return ["image/webp"]
        }
    }

    /// The format the file's first bytes show, whatever its name or label
    /// says. A response whose bytes do not match the expected format is
    /// rejected.
    static func sniff(_ data: Data) -> GifMediaFormat? {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 12 else { return nil }
        if bytes[0...3] == [0x47, 0x49, 0x46, 0x38] {
            return .gif  // "GIF8"
        }
        if bytes[0...3] == [0x52, 0x49, 0x46, 0x46], bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return .webp  // "RIFF" .... "WEBP"
        }
        if bytes[4...7] == [0x66, 0x74, 0x79, 0x70] {
            return .mp4  // .... "ftyp"
        }
        return nil
    }
}

/// One file that may show the GIF, in the order to try.
struct GifMediaCandidate: Equatable, Sendable {
    let url: URL
    let format: GifMediaFormat
    /// The size the page states, in pixels, before any media loads.
    let pixelSize: CGSize?

    init(url: URL, format: GifMediaFormat, pixelSize: CGSize? = nil) {
        self.url = url
        self.format = format
        self.pixelSize = pixelSize
    }
}

/// Giphy media URLs follow from the GIF's ID.
enum GiphyMedia {
    /// MP4 first: for a typical GIF it is a twentieth of the GIF's size and
    /// plays more smoothly. Stickers are transparent, which MP4 cannot
    /// carry, so they use animated WebP, then GIF.
    static func candidates(id: String, isSticker: Bool) -> [GifMediaCandidate] {
        let formats: [GifMediaFormat] = isSticker ? [.webp, .gif] : [.mp4, .gif]
        return formats.compactMap { format in
            URL(string: "https://media.giphy.com/media/\(id)/giphy.\(format.fileExtension)")
                .map { GifMediaCandidate(url: $0, format: format) }
        }
    }
}

/// Tenor media paths: /<id><format code>/<name>.<ext>, sometimes after an
/// "m" segment. The first 12 characters of the 16-character segment name
/// the GIF; the last 4 name the rendition ("AAPo" is the MP4).
enum TenorMedia {
    static let mp4FormatCode = "AAPo"
    private static let segmentLength = 16
    private static let gifIDLength = 12

    static func isMediaPath(_ components: [String]) -> Bool {
        mediaPath(components) != nil
    }

    /// For a media link: the MP4 rendition when the path follows the naming
    /// scheme, then the linked file itself when it is a format the chat
    /// plays. WebM is not one; it only names the GIF.
    static func candidates(forMediaLink url: URL) -> [GifMediaCandidate] {
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let path = mediaPath(components) else { return [] }
        let segment = path.segment
        let filename = path.filename
        var candidates: [GifMediaCandidate] = []
        let name = (filename as NSString).deletingPathExtension
        let linkedFormat = GifMediaFormat(pathExtension: (filename as NSString).pathExtension)
        if linkedFormat != .mp4,
           segment.count == segmentLength,
           let mp4 = URL(string: "https://media.tenor.com/\(segment.prefix(gifIDLength))\(mp4FormatCode)/\(name).mp4") {
            candidates.append(GifMediaCandidate(url: mp4, format: .mp4))
        }
        if let linkedFormat {
            candidates.append(GifMediaCandidate(url: url, format: linkedFormat))
        }
        return candidates
    }

    private static func mediaPath(_ components: [String]) -> (segment: String, filename: String)? {
        var rest = components[...]
        if rest.count == 3, rest.first == "m" {
            rest = rest.dropFirst()
        }
        guard rest.count == 2,
              let segment = rest.first,
              let filename = rest.last,
              (8...40).contains(segment.count),
              segment.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              ["gif", "mp4", "webp", "webm"].contains((filename as NSString).pathExtension.lowercased())
        else { return nil }
        return (segment, filename)
    }
}

/// Reads the media a Tenor page names from its Open Graph tags:
/// og:video (MP4 and WebM, each with a width and height) and og:image
/// (the GIF). Pure: it reads HTML already fetched.
enum TenorPageParser {
    private struct Entry {
        var url: URL?
        var type: String?
        var width: Double?
        var height: Double?

        var pixelSize: CGSize? {
            guard let width, let height, width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
    }

    private static let metaTag = SafeRegex.compile(#"<meta\b[^>]*>"#, options: [.caseInsensitive])
    private static let attribute = SafeRegex.compile(
        #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
    )

    /// MP4 renditions first, then GIF and WebP ones, each only on Tenor's
    /// media hosts.
    static func candidates(fromHTML html: String) -> [GifMediaCandidate] {
        var videos: [Entry] = []
        var images: [Entry] = []
        var twitterStream = Entry()

        for tag in metaTags(in: html) {
            guard let key = (tag["property"] ?? tag["name"])?.lowercased(),
                  let content = tag["content"]
            else { continue }
            switch key {
            case "og:video", "og:video:url":
                videos.append(Entry(url: URL(string: content)))
            case "og:video:secure_url":
                if videos.isEmpty { videos.append(Entry()) }
                videos[videos.count - 1].url = URL(string: content)
            case "og:video:type":
                if !videos.isEmpty { videos[videos.count - 1].type = content.lowercased() }
            case "og:video:width":
                if !videos.isEmpty { videos[videos.count - 1].width = Double(content) }
            case "og:video:height":
                if !videos.isEmpty { videos[videos.count - 1].height = Double(content) }
            case "og:image", "og:image:url":
                images.append(Entry(url: URL(string: content)))
            case "og:image:secure_url":
                if images.isEmpty { images.append(Entry()) }
                images[images.count - 1].url = URL(string: content)
            case "og:image:type":
                if !images.isEmpty { images[images.count - 1].type = content.lowercased() }
            case "og:image:width":
                if !images.isEmpty { images[images.count - 1].width = Double(content) }
            case "og:image:height":
                if !images.isEmpty { images[images.count - 1].height = Double(content) }
            case "twitter:player:stream":
                twitterStream.url = URL(string: content)
            case "twitter:player:stream:content_type":
                twitterStream.type = content.lowercased()
            case "twitter:player:width":
                twitterStream.width = Double(content)
            case "twitter:player:height":
                twitterStream.height = Double(content)
            default:
                continue
            }
        }

        var candidates: [GifMediaCandidate] = []
        func add(_ entry: Entry, allowed: Set<GifMediaFormat>) {
            guard let url = entry.url,
                  GifHostPolicy.isAllowed(url),
                  let host = url.host?.lowercased(),
                  GifHostPolicy.isTenorMediaHost(host),
                  let format = format(of: entry),
                  allowed.contains(format),
                  !candidates.contains(where: { $0.url == url })
            else { return }
            candidates.append(GifMediaCandidate(url: url, format: format, pixelSize: entry.pixelSize))
        }
        videos.forEach { add($0, allowed: [.mp4]) }
        add(twitterStream, allowed: [.mp4])
        images.forEach { add($0, allowed: [.gif, .webp]) }
        return candidates
    }

    private static func format(of entry: Entry) -> GifMediaFormat? {
        if let type = entry.type {
            switch type {
            case "video/mp4": return .mp4
            case "image/gif": return .gif
            case "image/webp": return .webp
            default: return nil
            }
        }
        return entry.url.flatMap { GifMediaFormat(pathExtension: $0.pathExtension) }
    }

    /// Each meta tag's attributes, names lowercased, values unescaped.
    private static func metaTags(in html: String) -> [[String: String]] {
        let ns = html as NSString
        return metaTag.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { match in
            let tag = ns.substring(with: match.range)
            let tagNS = tag as NSString
            var attributes: [String: String] = [:]
            for attributeMatch in attribute.matches(in: tag, range: NSRange(location: 0, length: tagNS.length)) {
                let name = tagNS.substring(with: attributeMatch.range(at: 1)).lowercased()
                let valueRange = attributeMatch.range(at: 2).location != NSNotFound
                    ? attributeMatch.range(at: 2)
                    : attributeMatch.range(at: 3)
                guard valueRange.location != NSNotFound, attributes[name] == nil else { continue }
                attributes[name] = unescapeEntities(tagNS.substring(with: valueRange))
            }
            return attributes
        }
    }

    /// The entities a URL or number in an attribute can hold.
    static func unescapeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
