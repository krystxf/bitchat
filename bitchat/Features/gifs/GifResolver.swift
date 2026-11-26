//
// GifResolver.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation

/// One HTTP response, read without following its redirect.
struct GifHTTPResponse: Sendable {
    let url: URL
    let statusCode: Int
    /// The Content-Type without parameters, lowercased.
    let mimeType: String?
    /// The Location header of a redirect.
    let location: String?
    let body: Data

    var isRedirect: Bool { (300...399).contains(statusCode) }
    var isSuccess: Bool { (200...299).contains(statusCode) }
}

/// Sends the GIF code's requests. The live one routes through Tor when Tor
/// is on; tests supply canned responses, so no test touches the network.
protocol GifHTTPFetching: Sendable {
    /// Sends one GET to an allowlisted URL and never follows a redirect:
    /// the caller checks each target first. Throws `tooLarge` past
    /// `maxBytes`; stops early, with what it has, once `stopMarker` arrives.
    func fetch(_ url: URL, maxBytes: Int, stopMarker: Data?) async throws -> GifHTTPResponse
}

enum GifLoadError: Error, Equatable {
    /// A link or redirect left the HTTPS allowlist.
    case notAllowed
    case badStatus(Int)
    case tooManyRedirects
    /// The page names no media the chat can play.
    case noMedia
    case tooLarge
    /// The bytes are not the format the link and the server claim.
    case unexpectedContent
    /// Tor is switched on but not connected, so nothing is sent.
    case torUnavailable
    case undecodable
}

/// A downloaded GIF, checked against its format.
struct GifDownloadedMedia: Sendable {
    let data: Data
    let format: GifMediaFormat
    /// The size the page stated, used until the file's own size is read.
    let pixelSize: CGSize?
}

/// Turns a GIF link into its media file: follows short links one checked
/// redirect at a time, reads a Tenor page's head, then downloads the first
/// rendition that loads.
struct GifResolver: Sendable {
    static let maxRedirects = 5
    /// A Tenor page's head ends in its first ~20 KB; the cap only guards
    /// against a page that never closes it.
    static let maxPageBytes = 1_048_576
    static let maxRedirectBodyBytes = 65_536
    /// The download cap for one media file.
    static let maxMediaBytes = 10 * 1_048_576

    let fetcher: GifHTTPFetching

    /// The media for a link: the first candidate that downloads and checks.
    func media(for link: GifLink) async throws -> GifDownloadedMedia {
        let candidates = try await candidates(for: link)
        guard !candidates.isEmpty else { throw GifLoadError.noMedia }
        var lastError: Error = GifLoadError.noMedia
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                return try await download(candidate)
            } catch let error as GifLoadError where error == .torUnavailable {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The renditions a link names, best first.
    func candidates(for link: GifLink) async throws -> [GifMediaCandidate] {
        var current = link
        for _ in 0...Self.maxRedirects {
            try Task.checkCancellation()
            switch current.source {
            case .giphy(let id, let isSticker):
                return GiphyMedia.candidates(id: id, isSticker: isSticker)
            case .tenorMedia:
                return TenorMedia.candidates(forMediaLink: current.url)
            case .nostrBuildMedia(let format):
                return [GifMediaCandidate(url: current.url, format: format)]
            case .giphyShortLink, .tenorShortLink:
                let response = try await fetcher.fetch(current.url, maxBytes: Self.maxRedirectBodyBytes, stopMarker: nil)
                current = try nextLink(after: response)
            case .tenorPage:
                let response = try await fetcher.fetch(
                    current.url,
                    maxBytes: Self.maxPageBytes,
                    stopMarker: Data("</head>".utf8)
                )
                if response.isRedirect {
                    current = try nextLink(after: response)
                    continue
                }
                guard response.isSuccess else { throw GifLoadError.badStatus(response.statusCode) }
                let html = String(decoding: response.body, as: UTF8.self)
                let candidates = TenorPageParser.candidates(fromHTML: html)
                guard !candidates.isEmpty else { throw GifLoadError.noMedia }
                return candidates
            }
        }
        throw GifLoadError.tooManyRedirects
    }

    /// Downloads one rendition, following redirects only within the
    /// allowlist, and checks that the label and the bytes both match.
    func download(_ candidate: GifMediaCandidate) async throws -> GifDownloadedMedia {
        var url = candidate.url
        for _ in 0...Self.maxRedirects {
            try Task.checkCancellation()
            let response = try await fetcher.fetch(url, maxBytes: Self.maxMediaBytes, stopMarker: nil)
            if response.isRedirect {
                guard let location = response.location,
                      let next = GifHostPolicy.redirectTarget(location: location, from: url)
                else { throw GifLoadError.notAllowed }
                url = next
                continue
            }
            guard response.isSuccess else { throw GifLoadError.badStatus(response.statusCode) }
            guard let mimeType = response.mimeType,
                  candidate.format.acceptedMimeTypes.contains(mimeType),
                  GifMediaFormat.sniff(response.body) == candidate.format
            else { throw GifLoadError.unexpectedContent }
            return GifDownloadedMedia(data: response.body, format: candidate.format, pixelSize: candidate.pixelSize)
        }
        throw GifLoadError.tooManyRedirects
    }

    /// The GIF link a redirect points to. A target off the allowlist, or one
    /// that is no GIF link, ends the resolution without a request.
    private func nextLink(after response: GifHTTPResponse) throws -> GifLink {
        guard response.isRedirect else { throw GifLoadError.badStatus(response.statusCode) }
        guard let location = response.location,
              let target = GifHostPolicy.redirectTarget(location: location, from: response.url),
              let link = GifLinkParser.parse(target)
        else { throw GifLoadError.notAllowed }
        return link
    }
}
