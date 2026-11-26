//
// GifRecentsStore.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation

/// A GIF in the picker's Recent tab: its link and shape, never the media.
/// The media stays in `GifMediaStore`'s cache.
struct RecentGif: Codable, Equatable, Sendable {
    /// The link exactly as the message held it.
    let link: String
    /// Width / height, when it was known.
    let aspectRatio: Double?
    /// When the message carrying it was sent.
    let date: Date
}

/// GIFs I sent, and GIFs I received and loaded, newest first, one entry
/// per link. Works offline: it reads only this device's own list.
///
/// Both message wipes (panic and extreme security mode's exit wipe) empty
/// it, as they empty the messages the links came from.
final class GifRecentsStore: @unchecked Sendable {
    static let shared = GifRecentsStore(defaults: .standard)
    static let defaultsKey = "gif.recents"
    static let maxEntries = 60

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: [RecentGif]?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Newest first.
    var entries: [RecentGif] {
        lock.withLock { load() }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Adds a GIF, or moves it up when this message is newer than the one it
    /// was last seen in. An older message showing the same GIF again (while
    /// scrolling back) leaves the order alone.
    func record(link: String, aspectRatio: CGFloat?, date: Date) {
        lock.withLock {
            var entries = load()
            let ratio = aspectRatio.map(Double.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            if let index = entries.firstIndex(where: { $0.link == link }) {
                let existing = entries[index]
                let newest = max(existing.date, date)
                let shape = existing.aspectRatio ?? ratio
                guard newest != existing.date || shape != existing.aspectRatio else { return }
                entries[index] = RecentGif(link: link, aspectRatio: shape, date: newest)
            } else {
                entries.append(RecentGif(link: link, aspectRatio: ratio, date: date))
            }
            entries.sort { $0.date > $1.date }
            if entries.count > Self.maxEntries {
                entries.removeLast(entries.count - Self.maxEntries)
            }
            save(entries)
        }
    }

    func removeAll() {
        lock.withLock {
            cached = []
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    private func load() -> [RecentGif] {
        if let cached { return cached }
        let decoded = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([RecentGif].self, from: $0) } ?? []
        cached = decoded
        return decoded
    }

    private func save(_ entries: [RecentGif]) {
        cached = entries
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
