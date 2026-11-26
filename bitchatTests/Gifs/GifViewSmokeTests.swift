//
// GifViewSmokeTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import SwiftUI
import Testing
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@testable import bitchat

@MainActor
@Suite("GIF views")
struct GifViewSmokeTests {
    @discardableResult
    private func mount<V: View>(_ view: V) -> AnyObject {
        #if os(iOS)
        let host = UIHostingController(rootView: view.frame(width: 280))
        _ = host.view
        host.view.layoutIfNeeded()
        return host
        #else
        let host = NSHostingView(rootView: view.frame(width: 280))
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        return host
        #endif
    }

    @Test func placeholderAndPlaybackRender() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-views-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = FakeGifFetcher()
        fetcher.respond("https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4", status: 404)
        fetcher.respond(
            "https://media.tenor.com/3w0Our6WmXUAAAAC/brick.gif",
            mimeType: "image/gif",
            body: try makeAnimatedGIF(width: 40, height: 20, frames: 3, delay: 0.1)
        )
        let store = GifMediaStore(directory: directory, resolver: GifResolver(fetcher: fetcher))
        let suite = "GifViewSmokeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recents = GifRecentsStore(defaults: defaults)
        let link = try #require(URL(string: "https://media.tenor.com/3w0Our6WmXUAAAAC/brick.gif").flatMap(GifLinkParser.parse))

        let placeholder = GifMessageView(link: link, messageID: "gif-1", isFromMe: false, isFavoriteSender: false, sentAt: Date(), store: store, recents: recents)
        _ = placeholder.body
        mount(placeholder)

        let asset = try await store.load(link)
        let loaded = GifMessageView(link: link, messageID: "gif-1", isFromMe: false, isFavoriteSender: false, sentAt: Date(), store: store, recents: recents)
        mount(loaded)
        mount(GifPlaybackView(asset: asset, isPlaying: true))
        mount(GifPlaybackView(asset: asset, isPlaying: false))

        #expect(GifFrameCache.loadFrames(for: asset.fileURL)?.images.count == 3)
    }

    @Test func pickerRendersWithFakeSources() throws {
        let suite = "GifViewSmokeTests.picker.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recents = GifRecentsStore(defaults: defaults)
        let picker = GifPickerView(
            sources: [RecentGIFSource(recents: recents), FakeGIFSource(id: NostrGIFSource.sourceID, supportsSearch: true)],
            recents: recents,
            onSend: { _ in }
        )
        _ = picker.body
        mount(picker)
    }
}
