//
// GifRecentsStoreTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

@Suite("GIF recents")
struct GifRecentsStoreTests {
    private func makeStore() throws -> (GifRecentsStore, UserDefaults, String) {
        let suite = "GifRecentsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (GifRecentsStore(defaults: defaults), defaults, suite)
    }

    private let a = "https://giphy.com/gifs/3o7btPCcdNniyf0ArS"
    private let b = "https://tenor.com/view/brick-gif-16072518840379414901"
    private let c = "https://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif"

    @Test func newestComesFirst() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record(link: a, aspectRatio: 1.5, date: Date(timeIntervalSince1970: 100))
        store.record(link: b, aspectRatio: nil, date: Date(timeIntervalSince1970: 300))
        store.record(link: c, aspectRatio: 1, date: Date(timeIntervalSince1970: 200))

        #expect(store.entries.map(\.link) == [b, c, a])
        #expect(store.entries.last?.aspectRatio == 1.5)
    }

    @Test func aLinkAppearsOnceAndMovesUpOnlyForANewerMessage() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record(link: a, aspectRatio: nil, date: Date(timeIntervalSince1970: 100))
        store.record(link: b, aspectRatio: nil, date: Date(timeIntervalSince1970: 200))
        // An older message with the same GIF, seen while scrolling back.
        store.record(link: a, aspectRatio: 2, date: Date(timeIntervalSince1970: 50))
        #expect(store.entries.map(\.link) == [b, a])
        #expect(store.entries.last?.aspectRatio == 2)
        #expect(store.entries.last?.date == Date(timeIntervalSince1970: 100))

        // A newer message with it moves it to the top.
        store.record(link: a, aspectRatio: 2, date: Date(timeIntervalSince1970: 300))
        #expect(store.entries.map(\.link) == [a, b])
    }

    @Test func theListIsCapped() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        for index in 0..<(GifRecentsStore.maxEntries + 5) {
            store.record(link: "\(a)?n=\(index)", aspectRatio: nil, date: Date(timeIntervalSince1970: Double(index)))
        }

        #expect(store.entries.count == GifRecentsStore.maxEntries)
        #expect(store.entries.first?.link == "\(a)?n=\(GifRecentsStore.maxEntries + 4)")
    }

    @Test func entriesPersistAndRemoveAllClearsThem() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.record(link: c, aspectRatio: 1.2, date: Date(timeIntervalSince1970: 10))

        let reopened = GifRecentsStore(defaults: defaults)
        #expect(reopened.entries.map(\.link) == [c])

        reopened.removeAll()
        #expect(reopened.isEmpty)
        #expect(GifRecentsStore(defaults: defaults).isEmpty)
        #expect(defaults.object(forKey: GifRecentsStore.defaultsKey) == nil)
    }

    @Test func badShapesAreNotStored() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.record(link: a, aspectRatio: .infinity, date: Date())
        store.record(link: b, aspectRatio: 0, date: Date())
        #expect(store.entries.allSatisfy { $0.aspectRatio == nil })
    }
}
