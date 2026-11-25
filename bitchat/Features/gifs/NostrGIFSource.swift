//
// NostrGIFSource.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// GIF search over Nostr, with no API key.
///
/// GIFs are NIP-94 file metadata events (kind 1063, `m` tag `image/gif`).
/// gifbuddy.lol publishes many, hosted on nostr.build, with a size, a small
/// thumbnail and a description. Relays that implement NIP-50 answer a
/// `search` filter over them. As tested on 2026-11-25, wss://nostr.wine
/// answers with relevant results; wss://relay.ditto.pub adds a few and is
/// the one that lists gifbuddy's latest uploads for browsing.
///
/// Requests take the same route as GIF downloads (`GifNetworkRoute`): Tor
/// when it is on, failing closed while it is not connected. A search sends
/// its text to these relays; nothing is sent before the picker asks.
struct NostrGIFSource: GIFSource {
    static let sourceID = "nostr"
    static let searchRelays: [URL] = [
        URL(string: "wss://nostr.wine")!,
        URL(string: "wss://relay.ditto.pub")!
    ]
    /// gifbuddy.lol tags its uploads; browsing lists the latest of them.
    static let browseTag = "gifbuddy"
    static let pageSize = 30

    let relays: [URL]
    let client: NostrRelayQuerying

    init(relays: [URL] = NostrGIFSource.searchRelays, client: NostrRelayQuerying = NostrWebSocketQuery()) {
        self.relays = relays
        self.client = client
    }

    var id: String { Self.sourceID }
    var supportsSearch: Bool { true }

    func browse(after cursor: GIFPageCursor?) async throws -> GIFPage {
        try await page(NostrGIFFilter(search: nil, tag: Self.browseTag, until: cursor.flatMap { Int($0.value) }, limit: Self.pageSize))
    }

    func search(_ query: String, after cursor: GIFPageCursor?) async throws -> GIFPage {
        guard let text = NostrGIFFilter.searchText(query) else {
            return try await browse(after: cursor)
        }
        return try await page(NostrGIFFilter(search: text, tag: nil, until: cursor.flatMap { Int($0.value) }, limit: Self.pageSize))
    }

    /// Asks every relay at once and merges the answers in relay order, one
    /// item per link. Fails only when every relay failed.
    private func page(_ filter: NostrGIFFilter) async throws -> GIFPage {
        let results = await withTaskGroup(of: (Int, Result<[NostrEvent], Error>).self) { group in
            for (index, relay) in relays.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await client.events(from: relay, filter: filter)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[NostrEvent], Error>)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        var events: [NostrEvent] = []
        var errors: [Error] = []
        for result in results {
            switch result {
            case .success(let relayEvents): events += relayEvents
            case .failure(let error): errors.append(error)
            }
        }
        if events.isEmpty, errors.count == results.count, let first = errors.first {
            // Tor being down explains every other failure; say that one.
            if errors.contains(where: { ($0 as? GifLoadError) == .torUnavailable }) {
                throw GifLoadError.torUnavailable
            }
            throw first
        }
        try Task.checkCancellation()

        var seen: Set<URL> = []
        var items: [GIFPickerItem] = []
        for event in events {
            guard let item = NostrGIFEvent.item(from: event), seen.insert(item.link).inserted else { continue }
            items.append(item)
        }
        // Older than everything this page saw. A page of nothing ends it.
        let next = events.map(\.created_at).min().map { GIFPageCursor(value: String($0 - 1)) }
        return GIFPage(items: items, next: events.isEmpty ? nil : next)
    }
}

/// A REQ filter for GIF file events.
struct NostrGIFFilter: Equatable, Sendable {
    static let kind = 1063
    static let maxSearchLength = 100

    var search: String?
    /// A `t` tag the events must carry.
    var tag: String?
    var until: Int?
    var limit: Int

    /// The search text to send, or nil when there is none.
    static func searchText(_ query: String) -> String? {
        let trimmed = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxSearchLength))
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "kinds": [Self.kind],
            "#m": ["image/gif"],
            "limit": limit
        ]
        if let search { object["search"] = search }
        if let tag { object["#t"] = [tag] }
        if let until { object["until"] = until }
        return object
    }

    /// `["REQ", <id>, <filter>]`, as sent on the socket.
    func requestFrame(subscriptionID: String) -> String {
        Self.frame(["REQ", subscriptionID, jsonObject])
    }

    static func closeFrame(subscriptionID: String) -> String {
        frame(["CLOSE", subscriptionID])
    }

    private static func frame(_ array: [Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// One message a relay sends on a subscription.
enum NostrRelayFrame {
    case event(NostrEvent)
    case endOfStoredEvents
    case closed(reason: String)
    case notice(String)
    /// Another subscription's message, or one this client has no use for.
    case ignored

    static func parse(_ text: String, subscriptionID: String) -> NostrRelayFrame {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = array.first as? String
        else { return .ignored }
        switch type {
        case "EVENT":
            guard array.count >= 3,
                  array[1] as? String == subscriptionID,
                  let object = array[2] as? [String: Any],
                  let event = try? NostrEvent(from: object)
            else { return .ignored }
            return .event(event)
        case "EOSE":
            return array.count >= 2 && array[1] as? String == subscriptionID ? .endOfStoredEvents : .ignored
        case "CLOSED":
            guard array.count >= 2, array[1] as? String == subscriptionID else { return .ignored }
            return .closed(reason: array.count >= 3 ? (array[2] as? String ?? "") : "")
        case "NOTICE":
            return .notice(array.count >= 2 ? (array[1] as? String ?? "") : "")
        default:
            return .ignored
        }
    }
}

/// Reads a NIP-94 file event as a picker item.
enum NostrGIFEvent {
    static let maxTitleLength = 120

    /// Nil unless it is a GIF (or animated WebP) whose file the chat's GIF
    /// renderer accepts: a relay may return anything, so the media host
    /// allowlist decides what is ever fetched.
    static func item(from event: NostrEvent) -> GIFPickerItem? {
        guard event.kind == NostrGIFFilter.kind,
              let mime = firstValue("m", in: event.tags)?.lowercased(),
              mime == "image/gif" || mime == "image/webp",
              let link = firstValue("url", in: event.tags).flatMap(URL.init(string:)),
              GifLinkParser.parse(link) != nil
        else { return nil }
        // gifbuddy adds two thumbnails: nostr.build's small GIF, then a
        // Tenor still. The first one the renderer accepts is the preview.
        let thumbnails = event.tags.filter { $0.count >= 2 && $0[0] == "thumb" }.compactMap { URL(string: $0[1]) }
        let preview = thumbnails.first { GifLinkParser.parse($0)?.provider == .nostrBuild }
            ?? thumbnails.first { GifLinkParser.parse($0) != nil }
            ?? link
        return GIFPickerItem(
            link: link,
            previewURL: preview,
            aspectRatio: firstValue("dim", in: event.tags).flatMap(aspectRatio(fromDimensions:)),
            title: title(of: event)
        )
    }

    /// "498x328" → 498 / 328.
    static func aspectRatio(fromDimensions dimensions: String) -> Double? {
        let parts = dimensions.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0, width.isFinite, height.isFinite
        else { return nil }
        return width / height
    }

    private static func title(of event: NostrEvent) -> String? {
        let candidates = [firstValue("alt", in: event.tags), firstValue("summary", in: event.tags), event.content]
        for candidate in candidates {
            guard let line = candidate?.split(whereSeparator: \.isNewline).first else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(maxTitleLength)) }
        }
        return nil
    }

    private static func firstValue(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.count >= 2 && $0[0] == name }?[1]
    }
}

enum NostrGIFSearchError: Error, Equatable {
    /// The relay ended the subscription without results.
    case closed(reason: String)
}

/// Sends one subscription to one relay and collects its stored events.
/// Tests supply canned events, so no test opens a socket.
protocol NostrRelayQuerying: Sendable {
    func events(from relay: URL, filter: NostrGIFFilter) async throws -> [NostrEvent]
}

/// A short-lived WebSocket per query: connect, REQ, read until EOSE (or
/// CLOSED, or the time limit), CLOSE, disconnect. It goes through
/// `GifNetworkRoute`, so Tor carries it when Tor is on, and it never joins
/// the app's long-lived relay connections or their identity.
struct NostrWebSocketQuery: NostrRelayQuerying {
    static let directTimeout: TimeInterval = 12
    static let torTimeout: TimeInterval = 30
    static let maxMessageBytes = 256 * 1024

    func events(from relay: URL, filter: NostrGIFFilter) async throws -> [NostrEvent] {
        guard relay.scheme?.lowercased() == "wss" else { throw GifLoadError.notAllowed }
        let configuration = try await GifNetworkRoute.sessionConfiguration()
        let timeout = configuration.connectionProxyDictionary == nil ? Self.directTimeout : Self.torTimeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: relay)
        GifNetworkRoute.applyHeaders(to: &request)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = Self.maxMessageBytes
        task.resume()

        // Cancelling the socket ends a receive that is waiting.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            task.cancel(with: .goingAway, reason: nil)
        }
        defer { watchdog.cancel() }

        let subscriptionID = "gif-" + UUID().uuidString.prefix(8).lowercased()
        var events: [NostrEvent] = []
        do {
            try await task.send(.string(filter.requestFrame(subscriptionID: subscriptionID)))
            receiving: while events.count < filter.limit * 2 {
                let message = try await withTaskCancellationHandler {
                    try await task.receive()
                } onCancel: {
                    task.cancel(with: .goingAway, reason: nil)
                }
                guard case .string(let text) = message else { continue }
                switch NostrRelayFrame.parse(text, subscriptionID: subscriptionID) {
                case .event(let event):
                    events.append(event)
                case .endOfStoredEvents:
                    break receiving
                case .closed(let reason):
                    // auth-required, unsupported filter: nothing more comes.
                    if events.isEmpty { throw NostrGIFSearchError.closed(reason: reason) }
                    break receiving
                case .notice, .ignored:
                    continue
                }
            }
            try? await task.send(.string(NostrGIFFilter.closeFrame(subscriptionID: subscriptionID)))
        } catch {
            try Task.checkCancellation()
            // A relay that answered and then dropped still gave results.
            if events.isEmpty { throw error }
        }
        task.cancel(with: .normalClosure, reason: nil)
        return events
    }
}
