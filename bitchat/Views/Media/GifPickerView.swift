//
// GifPickerView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Picks a GIF and sends it at once, as Messages does.
///
/// Two tabs, neither needing an API key: Recent (GIFs I sent, received and
/// loaded; offline) and Nostr (NIP-50 search over GIF file events). The
/// picker fetches nothing until it opens; a search waits for a pause in
/// typing. A sent GIF is its link as a text message, so older apps get a
/// working link and this app shows the GIF.
struct GifPickerView: View {
    @StateObject private var model: GifPickerModel
    @Environment(\.dismiss) private var dismiss

    /// Search words that find good reactions in the Nostr index, which is
    /// English. They are search text, not interface copy.
    static let suggestions = ["Happy", "Thumbs Up", "LOL", "Love", "Yes", "No", "Thank You", "Wow", "Dance", "Cat"]

    private enum Strings {
        static let title = String(localized: "gif_picker.title", comment: "Title of the GIF picker sheet")
        static let recent = String(localized: "gif_picker.tab.recent", comment: "GIF picker tab with GIFs I sent or loaded recently")
        static let searchPrompt = String(localized: "gif_picker.search_prompt", comment: "Placeholder of the GIF picker's search field, which searches GIFs on Nostr")
        static func relaysCaption(_ relays: String) -> String {
            String(
                format: String(localized: "gif_picker.relays_caption", comment: "Caption under the GIF search field naming the relays searches are sent to; the argument is a list of relay hosts"),
                locale: .current,
                relays
            )
        }
        static let emptyRecentTitle = String(localized: "gif_picker.empty.recent.title", comment: "Title when the GIF picker's Recent tab has nothing")
        static let emptyRecentMessage = String(localized: "gif_picker.empty.recent.message", comment: "Explains what fills the GIF picker's Recent tab")
        static let emptySearchTitle = String(localized: "gif_picker.empty.search.title", comment: "Title when a GIF search finds nothing")
        static let errorTitle = String(localized: "gif_picker.error.title", comment: "Title when the GIF picker could not load GIFs")
        static let torUnavailable = String(localized: "media.gif.tor_unavailable", comment: "Caption on a GIF that did not load because Tor is on but not connected")
        static let retry = String(localized: "gif_picker.action.retry", comment: "Button that loads the GIF picker's list again after an error")
        static let clearSearch = String(localized: "gif_picker.accessibility.clear_search", comment: "Accessibility label of the button that clears the GIF search text")
        static let sendHint = String(localized: "gif_picker.accessibility.send_hint", comment: "Accessibility hint on a GIF in the picker; activating it sends the GIF")
    }

    init(
        sources: [GIFSource] = [RecentGIFSource(), NostrGIFSource()],
        recents: GifRecentsStore = .shared,
        onSend: @escaping (String) -> Void
    ) {
        _model = StateObject(wrappedValue: GifPickerModel(sources: sources, recents: recents, sendLink: onSend))
    }

    private var isNostrSelected: Bool {
        model.selectedSourceID == NostrGIFSource.sourceID
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 8)
            if isNostrSelected {
                if model.query.isEmpty {
                    suggestionChips
                        .padding(.top, 10)
                }
                Text(verbatim: Strings.relaysCaption(NostrGIFSource.searchRelays.compactMap(\.host).joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(.novaSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheetChrome(
            title: Text(verbatim: Strings.title),
            onClose: { dismiss() },
            principal: { sourcePicker }
        )
        // Fires on open and whenever the tab or the search text changes;
        // a new value cancels the wait for the old one.
        .task(id: model.requestKey) {
            if model.activeQuery != nil {
                try? await Task.sleep(nanoseconds: GifPickerModel.searchDebounce)
                guard !Task.isCancelled else { return }
            }
            await model.reload()
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 520, idealHeight: 640)
        #endif
    }

    // MARK: - Header

    private var sourcePicker: some View {
        Picker(selection: $model.selectedSourceID) {
            ForEach(model.sources, id: \.id) { source in
                Text(verbatim: tabTitle(for: source)).tag(source.id)
            }
        } label: {
            Text(verbatim: Strings.title)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private func tabTitle(for source: GIFSource) -> String {
        switch source.id {
        case RecentGIFSource.sourceID: return Strings.recent
        // The network's name, the same in every language.
        case NostrGIFSource.sourceID: return "Nostr"
        default: return source.id
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.novaSecondaryText)
                .accessibilityHidden(true)
            TextField(Strings.searchPrompt, text: $model.query)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.novaSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.clearSearch)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(in: Capsule())
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { term in
                    Button {
                        model.query = term
                    } label: {
                        Text(verbatim: term)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassSurface(in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
        case .empty:
            if model.selectedSourceID == RecentGIFSource.sourceID {
                stateView(symbol: "clock", title: Strings.emptyRecentTitle, message: Strings.emptyRecentMessage)
            } else {
                stateView(symbol: "magnifyingglass", title: Strings.emptySearchTitle)
            }
        case .failed(let torUnavailable):
            stateView(
                symbol: torUnavailable ? "network.slash" : "exclamationmark.triangle",
                title: torUnavailable ? Strings.torUnavailable : Strings.errorTitle,
                showsRetry: true
            )
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 200), spacing: 6)], spacing: 6) {
                ForEach(model.items) { item in
                    GifPickerCell(item: item, sendHint: Strings.sendHint) {
                        model.send(item)
                        dismiss()
                    }
                    .task {
                        await model.loadMoreIfNeeded(currentItem: item)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            if model.isLoadingMore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding()
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func stateView(symbol: String, title: String, message: String? = nil, showsRetry: Bool = false) -> some View {
        SheetEmptyState(title: title, systemImage: symbol, message: message) {
            if showsRetry {
                Button(Strings.retry) {
                    Task { await model.reload() }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// One GIF in the picker: its small rendition, looping while on screen
/// (held still under Reduce Motion). A tap sends it.
private struct GifPickerCell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let item: GIFPickerItem
    let sendHint: String
    let onSend: () -> Void
    private let preview: GifLink?
    private let store: GifMediaStore

    @State private var asset: GifAsset?
    @State private var failed = false
    @State private var isOnScreen = false

    init(item: GIFPickerItem, sendHint: String, store: GifMediaStore = .shared, onSend: @escaping () -> Void) {
        self.item = item
        self.sendHint = sendHint
        self.onSend = onSend
        self.store = store
        let preview = GifLinkParser.parse(item.previewURL) ?? GifLinkParser.parse(item.link)
        self.preview = preview
        _asset = State(initialValue: preview.flatMap(store.cachedAsset(for:)))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        Button(action: onSend) {
            shape
                .fill(Color.novaSurfaceRaised)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let asset {
                        GifPlaybackView(
                            asset: asset,
                            isPlaying: isOnScreen && scenePhase == .active && !reduceMotion,
                            profile: .preview
                        )
                    } else if failed {
                        Image(systemName: "photo")
                            .foregroundStyle(.novaSecondaryText)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .task(id: item.previewURL) {
            guard asset == nil, let preview else {
                failed = preview == nil
                return
            }
            do {
                asset = try await store.load(preview)
            } catch {
                failed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.title ?? "GIF"))
        .accessibilityHint(Text(verbatim: sendHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSend() }
    }
}
