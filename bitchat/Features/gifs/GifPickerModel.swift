//
// GifPickerModel.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// The GIF picker's state: which source is on screen, what it found, and
/// paging. Sources do the fetching; this only orders the requests and
/// drops answers that arrive after the person moved on.
@MainActor
final class GifPickerModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case failed(torUnavailable: Bool)
    }

    @Published private(set) var items: [GIFPickerItem] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isLoadingMore = false
    @Published var selectedSourceID: String
    @Published var query: String = "" {
        didSet { switchToSearchableSourceIfNeeded() }
    }

    let sources: [GIFSource]
    private let recents: GifRecentsStore
    private let sendLink: (String) -> Void
    private var next: GIFPageCursor?
    /// Bumped by every new first page, so a late answer for an old search
    /// or tab cannot land on the new one.
    private var generation = 0

    /// Wait this long after the last keystroke before searching.
    static let searchDebounce: UInt64 = 350_000_000
    /// Load the next page when one of the last few items shows.
    static let prefetchDistance = 6

    init(sources: [GIFSource], recents: GifRecentsStore, sendLink: @escaping (String) -> Void) {
        self.sources = sources
        self.recents = recents
        self.sendLink = sendLink
        // Recent first when it has something: it works offline and sends
        // nothing anywhere. Otherwise the first source that can search.
        let recentHasItems = !recents.isEmpty && sources.contains { $0.id == RecentGIFSource.sourceID }
        selectedSourceID = recentHasItems
            ? RecentGIFSource.sourceID
            : (sources.first { $0.supportsSearch } ?? sources.first)?.id ?? RecentGIFSource.sourceID
    }

    var selectedSource: GIFSource? {
        sources.first { $0.id == selectedSourceID }
    }

    /// The search text to send, or nil to browse.
    var activeQuery: String? {
        guard selectedSource?.supportsSearch == true else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Changes whenever the first page must be fetched again.
    var requestKey: String {
        "\(selectedSourceID)|\(activeQuery ?? "")"
    }

    /// Fetches the first page for the current source and search.
    func reload() async {
        generation += 1
        let generation = generation
        next = nil
        items = []
        isLoadingMore = false
        phase = .loading
        guard let source = selectedSource else {
            phase = .empty
            return
        }
        let query = activeQuery
        do {
            let page = try await Self.page(from: source, query: query, after: nil)
            guard generation == self.generation else { return }
            items = Self.unique(page.items)
            next = page.next
            phase = items.isEmpty ? .empty : .loaded
        } catch {
            guard generation == self.generation, !(error is CancellationError) else { return }
            phase = .failed(torUnavailable: (error as? GifLoadError) == .torUnavailable)
        }
    }

    /// Loads the next page once one of the last items shows.
    func loadMoreIfNeeded(currentItem: GIFPickerItem) async {
        guard let cursor = next,
              !isLoadingMore,
              phase == .loaded,
              items.suffix(Self.prefetchDistance).contains(where: { $0.id == currentItem.id }),
              let source = selectedSource
        else { return }
        let generation = generation
        let query = activeQuery
        isLoadingMore = true
        defer {
            if generation == self.generation { isLoadingMore = false }
        }
        do {
            let page = try await Self.page(from: source, query: query, after: cursor)
            guard generation == self.generation else { return }
            let known = Set(items.map(\.id))
            let fresh = Self.unique(page.items).filter { !known.contains($0.id) }
            items += fresh
            // A page with nothing new ends the list, so paging cannot spin.
            next = fresh.isEmpty ? nil : page.next
        } catch {
            guard generation == self.generation else { return }
            // Keep what is on screen; stop paging rather than retry in a loop.
            next = nil
        }
    }

    /// Sends the GIF's link as a message and puts it at the top of Recent.
    func send(_ item: GIFPickerItem) {
        let link = item.link.absoluteString
        recents.record(link: link, aspectRatio: item.aspectRatio.map { CGFloat($0) }, date: Date())
        sendLink(link)
    }

    /// Typing while on a tab that cannot search moves to one that can.
    private func switchToSearchableSourceIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedSource?.supportsSearch != true,
              let searchable = sources.first(where: { $0.supportsSearch })
        else { return }
        selectedSourceID = searchable.id
    }

    private static func page(from source: GIFSource, query: String?, after cursor: GIFPageCursor?) async throws -> GIFPage {
        if let query {
            return try await source.search(query, after: cursor)
        }
        return try await source.browse(after: cursor)
    }

    private static func unique(_ items: [GIFPickerItem]) -> [GIFPickerItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }
}
