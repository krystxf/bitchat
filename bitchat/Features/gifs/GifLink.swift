//
// GifLink.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// The GIF services whose links the chat shows as animations.
enum GifProvider: String, Sendable {
    case giphy
    case tenor

    /// The site named on the tap-to-load placeholder.
    var displayHost: String {
        switch self {
        case .giphy: return "giphy.com"
        case .tenor: return "tenor.com"
        }
    }
}

/// A Giphy or Tenor link found in a message.
///
/// A GIF travels as an ordinary text message holding its link, so older apps
/// show the link as text. Only HTTPS links on the hosts in `GifHostPolicy`
/// are recognized; everything else stays plain text.
struct GifLink: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// A Giphy GIF named by its ID. The media URL follows from the ID,
        /// so nothing is fetched to resolve it.
        case giphy(id: String, isSticker: Bool)
        /// A gph.is short link. One redirect names the Giphy page.
        case giphyShortLink
        /// A Tenor page. Its HTML head names the media.
        case tenorPage(id: String)
        /// A tenor.com/<code>.gif short link. It redirects to the page.
        case tenorShortLink
        /// A file on Tenor's media hosts.
        case tenorMedia
    }

    /// The link as the message holds it.
    let url: URL
    let source: Source

    var provider: GifProvider {
        switch source {
        case .giphy, .giphyShortLink: return .giphy
        case .tenorPage, .tenorShortLink, .tenorMedia: return .tenor
        }
    }

    /// The key the cache stores the media under. Links that name the same
    /// GIF by ID share one entry; other links use their own text.
    var cacheKey: String {
        switch source {
        case .giphy(let id, let isSticker):
            return isSticker ? "giphy-sticker:\(id)" : "giphy:\(id)"
        case .tenorPage(let id):
            return "tenor:\(id)"
        case .giphyShortLink, .tenorShortLink, .tenorMedia:
            return "url:\(url.absoluteString)"
        }
    }
}

/// Which URLs the GIF code may fetch: HTTPS on Giphy's and Tenor's own
/// hosts only, checked for the link itself and again after every redirect.
enum GifHostPolicy {
    static let giphyPageHosts: Set<String> = ["giphy.com", "www.giphy.com"]
    static let giphyShortLinkHosts: Set<String> = ["gph.is"]
    static let tenorPageHosts: Set<String> = ["tenor.com", "www.tenor.com"]

    /// Giphy media: i.giphy.com, media.giphy.com and media0-9.giphy.com.
    static func isGiphyMediaHost(_ host: String) -> Bool {
        host == "i.giphy.com" || isNumberedMediaHost(host, domain: "giphy.com")
    }

    /// Tenor media: c.tenor.com, media.tenor.com and media0-9.tenor.com.
    static func isTenorMediaHost(_ host: String) -> Bool {
        host == "c.tenor.com" || isNumberedMediaHost(host, domain: "tenor.com")
    }

    static func isAllowedHost(_ host: String) -> Bool {
        giphyPageHosts.contains(host)
            || giphyShortLinkHosts.contains(host)
            || tenorPageHosts.contains(host)
            || isGiphyMediaHost(host)
            || isTenorMediaHost(host)
    }

    /// Whether the GIF code may send a request to this URL.
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              isAllowedHost(host),
              url.user == nil,
              url.password == nil
        else { return false }
        if let port = url.port, port != 443 { return false }
        return true
    }

    /// The target of a redirect, resolved against the URL that sent it.
    /// Nil when the target leaves the allowlist or is not HTTPS.
    static func redirectTarget(location: String, from base: URL) -> URL? {
        guard let target = URL(string: location, relativeTo: base)?.absoluteURL,
              isAllowed(target)
        else { return nil }
        return target
    }

    /// "media.<domain>" or "media<digit>.<domain>".
    private static func isNumberedMediaHost(_ host: String, domain: String) -> Bool {
        guard host.hasSuffix("." + domain) else { return false }
        let label = host.dropLast(domain.count + 1)
        guard label.hasPrefix("media") else { return false }
        let suffix = label.dropFirst("media".count)
        return suffix.isEmpty || (suffix.count == 1 && suffix.first?.isASCIIDigit == true)
    }
}

/// Reads Giphy and Tenor links. Pure: nothing here touches the network.
enum GifLinkParser {
    /// The GIF link a URL names, or nil when it is not one.
    static func parse(_ url: URL) -> GifLink? {
        guard GifHostPolicy.isAllowed(url),
              let host = url.host?.lowercased()
        else { return nil }
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        if GifHostPolicy.giphyPageHosts.contains(host) {
            return parseGiphyPage(url, components: components)
        }
        if GifHostPolicy.giphyShortLinkHosts.contains(host) {
            return components.isEmpty ? nil : GifLink(url: url, source: .giphyShortLink)
        }
        if GifHostPolicy.isGiphyMediaHost(host) {
            return parseGiphyMedia(url, host: host, components: components)
        }
        if GifHostPolicy.tenorPageHosts.contains(host) {
            return parseTenorPage(url, components: components)
        }
        if GifHostPolicy.isTenorMediaHost(host) {
            return TenorMedia.isMediaPath(components) ? GifLink(url: url, source: .tenorMedia) : nil
        }
        return nil
    }

    /// giphy.com/gifs/<slug>-<id>, /gifs/<id>, /stickers/<slug>-<id> and
    /// /embed/<id>. Anything after the ID segment (/fullscreen) is ignored.
    private static func parseGiphyPage(_ url: URL, components: [String]) -> GifLink? {
        guard components.count >= 2 else { return nil }
        let kind = components[0].lowercased()
        let segment = components[1]
        let id: Substring
        switch kind {
        case "gifs", "stickers":
            id = segment.split(separator: "-").last ?? Substring(segment)
        case "embed":
            id = Substring(segment)
        default:
            return nil
        }
        guard isGiphyID(id) else { return nil }
        return GifLink(url: url, source: .giphy(id: String(id), isSticker: kind == "stickers"))
    }

    /// media.giphy.com/media/<id>/<file>, the same with a "v1.<token>"
    /// segment before the ID, and i.giphy.com/<id>.<ext>.
    private static func parseGiphyMedia(_ url: URL, host: String, components: [String]) -> GifLink? {
        let id: String
        if host == "i.giphy.com", components.count == 1 {
            id = (components[0] as NSString).deletingPathExtension
        } else {
            guard components.count >= 3,
                  components[0].lowercased() == "media",
                  isMediaFilename(components[components.count - 1])
            else { return nil }
            id = components[components.count - 2]
        }
        guard isGiphyID(Substring(id)) else { return nil }
        return GifLink(url: url, source: .giphy(id: id, isSticker: false))
    }

    /// tenor.com/view/<slug>-<number>, with an optional locale segment
    /// first (tenor.com/en-GB/view/...), and tenor.com/<code>.gif.
    private static func parseTenorPage(_ url: URL, components: [String]) -> GifLink? {
        if components.count == 1 {
            let name = components[0]
            let ext = (name as NSString).pathExtension.lowercased()
            let code = (name as NSString).deletingPathExtension
            guard ext == "gif",
                  (3...16).contains(code.count),
                  code.allSatisfy({ $0.isASCIILetterOrDigit })
            else { return nil }
            return GifLink(url: url, source: .tenorShortLink)
        }
        var rest = components[...]
        if rest.count == 3, isLocaleSegment(rest[rest.startIndex]) {
            rest = rest.dropFirst()
        }
        guard rest.count == 2,
              rest[rest.startIndex].lowercased() == "view",
              let id = rest[rest.index(after: rest.startIndex)].split(separator: "-").last,
              (4...24).contains(id.count),
              id.allSatisfy({ $0.isASCIIDigit })
        else { return nil }
        return GifLink(url: url, source: .tenorPage(id: String(id)))
    }

    /// Giphy IDs are random base-62 strings. A real one practically always
    /// holds a digit or a capital letter; requiring one keeps a slug-only
    /// link ("giphy.com/gifs/happy-birthday") from passing as an ID.
    private static func isGiphyID(_ id: Substring) -> Bool {
        (6...40).contains(id.count)
            && id.allSatisfy { $0.isASCIILetterOrDigit }
            && id.contains { $0.isASCIIDigit || ($0.isASCII && $0.isUppercase) }
    }

    private static func isMediaFilename(_ name: String) -> Bool {
        ["gif", "mp4", "webp"].contains((name as NSString).pathExtension.lowercased())
    }

    /// "de", "fil", "en-GB", "zh-CN", "pt-BR".
    private static func isLocaleSegment(_ segment: String) -> Bool {
        let parts = segment.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              (2...3).contains(parts[0].count),
              parts[0].allSatisfy({ $0.isASCII && $0.isLetter && $0.isLowercase })
        else { return false }
        if parts.count == 2 {
            return (2...4).contains(parts[1].count) && parts[1].allSatisfy { $0.isASCIILetterOrDigit }
        }
        return true
    }
}

/// What a message holds when it carries a GIF link.
struct GifMessageContent: Equatable, Sendable {
    let link: GifLink
    /// The message is the link alone (plus whitespace), so the GIF stands
    /// in for the text bubble, as an image does.
    let isLinkOnly: Bool
}

/// Finds the first GIF link in message text.
enum GifMessageDetector {
    /// Longer messages are never scanned: the collapse and rich-formatting
    /// guards treat them as untrusted layout work already.
    static let maxScannedLength = 4000

    private final class Box {
        let content: GifMessageContent?
        init(_ content: GifMessageContent?) { self.content = content }
    }

    /// Rows re-render far more often than their text changes.
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 512
        return cache
    }()

    /// The cached form of `detect(in:)`.
    static func content(in text: String) -> GifMessageContent? {
        if let cached = cache.object(forKey: text as NSString) {
            return cached.content
        }
        let content = detect(in: text)
        cache.setObject(Box(content), forKey: text as NSString)
        return content
    }

    static func detect(in text: String) -> GifMessageContent? {
        guard text.count <= maxScannedLength, mentionsGifHost(text) else { return nil }
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        for token in tokens {
            let candidate = token.trimmingCharacters(in: wrappingPunctuation)
            guard candidate.lowercased().hasPrefix("https://"),
                  let url = URL(string: candidate),
                  let link = GifLinkParser.parse(url)
            else { continue }
            return GifMessageContent(link: link, isLinkOnly: tokens.count == 1)
        }
        return nil
    }

    /// Characters people put around a pasted link: quotes, brackets and the
    /// sentence's own punctuation.
    private static let wrappingPunctuation = CharacterSet(charactersIn: "<>()[]{}\"'`.,;:!?")

    /// A cheap test that skips the token scan for nearly every message.
    private static func mentionsGifHost(_ text: String) -> Bool {
        text.range(of: "giphy.com", options: .caseInsensitive) != nil
            || text.range(of: "gph.is", options: .caseInsensitive) != nil
            || text.range(of: "tenor.com", options: .caseInsensitive) != nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetterOrDigit: Bool { isASCII && (isLetter || isNumber) }
}
