//
// GifMessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

extension EnvironmentValues {
    /// Opens a media file in the full-screen preview. The message list sets
    /// it; GIF rows use it to open a loaded GIF.
    var openMediaPreview: ((URL) -> Void)? {
        get { self[OpenMediaPreviewKey.self] }
        set { self[OpenMediaPreviewKey.self] = newValue }
    }
}

private struct OpenMediaPreviewKey: EnvironmentKey {
    static let defaultValue: ((URL) -> Void)? = nil
}

/// A Giphy or Tenor GIF in the chat, shown like an image message.
///
/// GIFs I sent, and GIFs from favorites when "show images from favorites"
/// is on, load by themselves (`GifLoadPolicy`). Every other GIF shows a
/// placeholder naming the site and loads only after a tap. A GIF already in
/// the cache shows at once: showing it sends nothing.
///
/// The card keeps the GIF's aspect ratio from the cache's record before any
/// frame loads, so rows do not jump while scrolling. It plays silently on a
/// loop while on screen and the app is active. Under Reduce Motion it holds
/// the first frame and offers a play button.
struct GifMessageView: View {
    @ThemedPalette private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openMediaPreview) private var openMediaPreview
    /// Settings toggle shared with images: favorites' media skips the gate.
    @AppStorage(MediaRevealSettings.autoRevealFavoritesKey) private var autoRevealFavorites = false

    private let link: GifLink
    private let messageID: String
    private let isFromMe: Bool
    private let isFavoriteSender: Bool
    /// When the message was sent; orders the picker's Recent tab.
    private let sentAt: Date
    private let store: GifMediaStore
    private let recents: GifRecentsStore

    private enum Phase: Equatable {
        case waitingForTap
        case loading
        case loaded(GifAsset)
        case failed(torUnavailable: Bool)
    }

    @State private var phase: Phase
    @State private var aspectRatio: CGFloat
    @State private var isOnScreen = false
    @State private var playsDespiteReduceMotion = false

    /// Before the size is known: the shape most GIFs come close to.
    static let defaultAspectRatio: CGFloat = 4.0 / 3.0

    private enum Strings {
        static func placeholderTitle(_ host: String) -> String {
            String(
                format: String(localized: "media.gif.placeholder_title", comment: "Placeholder title on a GIF that has not loaded; the argument is the site, such as giphy.com"),
                locale: .current,
                host
            )
        }
        static let tapToLoad = String(localized: "media.gif.tap_to_load", comment: "Caption on a GIF placeholder; a tap loads the GIF from Giphy or Tenor")
        static let loadFailed = String(localized: "media.gif.load_failed", comment: "Title on a GIF placeholder when the GIF could not be loaded")
        static let tapToRetry = String(localized: "media.gif.tap_to_retry", comment: "Caption on a GIF that failed to load; a tap tries again")
        static let torUnavailable = String(localized: "media.gif.tor_unavailable", comment: "Caption on a GIF that did not load because Tor is on but not connected")
        static let loadHint = String(localized: "media.gif.accessibility.hint.load", comment: "Accessibility hint for a GIF placeholder; activating it loads the GIF")
        static let openHint = String(localized: "media.image.accessibility.hint.open", comment: "Accessibility hint for a revealed image; activating it opens the image full screen")
        static let play = String(localized: "media.gif.accessibility.play", comment: "Button that plays a GIF held still by Reduce Motion")
        static let pause = String(localized: "media.gif.accessibility.pause", comment: "Button that stops a GIF playing under Reduce Motion")
    }

    init(
        link: GifLink,
        messageID: String,
        isFromMe: Bool,
        isFavoriteSender: Bool,
        sentAt: Date,
        store: GifMediaStore = .shared,
        recents: GifRecentsStore = .shared
    ) {
        self.link = link
        self.messageID = messageID
        self.isFromMe = isFromMe
        self.isFavoriteSender = isFavoriteSender
        self.sentAt = sentAt
        self.store = store
        self.recents = recents
        let cached = store.cachedAsset(for: link)
        _phase = State(initialValue: cached.map(Phase.loaded) ?? .waitingForTap)
        _aspectRatio = State(initialValue: Self.displayAspectRatio(cached?.aspectRatio))
    }

    /// Extreme shapes are cropped rather than shown as a sliver or a tower.
    static func displayAspectRatio(_ ratio: CGFloat?) -> CGFloat {
        guard let ratio, ratio.isFinite, ratio > 0 else { return defaultAspectRatio }
        return min(max(ratio, 0.5), 2.5)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MessageBubbleStyle.cornerRadius, style: .continuous)
    }

    private var isPlaying: Bool {
        isOnScreen && scenePhase == .active && (!reduceMotion || playsDespiteReduceMotion)
    }

    private var loadedAsset: GifAsset? {
        if case .loaded(let asset) = phase { return asset }
        return nil
    }

    var body: some View {
        // A Button, not a tap gesture: the DM sheet's high-priority swipe
        // gesture starves descendant tap gestures (see BlockRevealImageView).
        Button(action: handleTap) {
            content
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(shape)
                .overlay(shape.stroke(Color.gray.opacity(0.2), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            if loadedAsset != nil {
                gifBadge
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if loadedAsset != nil, reduceMotion, !playsDespiteReduceMotion {
                playButton
            }
        }
        .overlay(alignment: .topTrailing) {
            if loadedAsset != nil, reduceMotion, playsDespiteReduceMotion {
                pauseButton
                    .padding(8)
            }
        }
        .onAppear {
            isOnScreen = true
            if let asset = loadedAsset {
                rememberAsRecent(asset)
            } else if phase == .waitingForTap, shouldLoadWithoutTap {
                load()
            }
        }
        .onDisappear {
            isOnScreen = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.placeholderTitle(link.provider.displayHost))
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(phase == .loading ? [] : .isButton)
        // The ignored children include the Button, so activation is wired
        // here explicitly.
        .accessibilityAction { handleTap() }
        .accessibilityActions {
            if loadedAsset != nil, reduceMotion {
                if playsDespiteReduceMotion {
                    Button(Strings.pause) { playsDespiteReduceMotion = false }
                } else {
                    Button(Strings.play) { playsDespiteReduceMotion = true }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let asset = loadedAsset {
            GifPlaybackView(asset: asset, isPlaying: isPlaying)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        shape
            .fill(palette.secondary.opacity(0.15))
            .overlay {
                VStack(spacing: 6) {
                    placeholderIcon
                    Text(verbatim: placeholderTitle)
                        .bitchatFont(size: 13, weight: .semibold)
                        .foregroundColor(palette.primary)
                    if let caption = placeholderCaption {
                        Text(verbatim: caption)
                            .bitchatFont(size: 11, weight: .medium)
                            .foregroundColor(palette.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(12)
            }
    }

    @ViewBuilder
    private var placeholderIcon: some View {
        switch phase {
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.bitchatSystem(size: 20, weight: .semibold))
                .foregroundColor(palette.secondary)
        case .waitingForTap, .loaded:
            gifBadge
        }
    }

    private var placeholderTitle: String {
        if case .failed = phase { return Strings.loadFailed }
        return Strings.placeholderTitle(link.provider.displayHost)
    }

    private var placeholderCaption: String? {
        switch phase {
        case .waitingForTap: return Strings.tapToLoad
        case .failed(let torUnavailable): return torUnavailable ? Strings.torUnavailable : Strings.tapToRetry
        case .loading, .loaded: return nil
        }
    }

    /// "GIF" on Liquid Glass, as a GIF keyboard labels its results.
    private var gifBadge: some View {
        Text(verbatim: "GIF")
            .bitchatFont(size: 11, weight: .bold)
            .foregroundColor(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassSurface(in: Capsule())
    }

    private var playButton: some View {
        Button {
            playsDespiteReduceMotion = true
        } label: {
            Image(systemName: "play.fill")
                .font(.bitchatSystem(size: 18, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .glassButtonStyle()
        .circularButtonShape()
        .controlSize(.large)
        .accessibilityLabel(Strings.play)
    }

    private var pauseButton: some View {
        Button {
            playsDespiteReduceMotion = false
        } label: {
            Image(systemName: "pause.fill")
                .font(.bitchatSystem(size: 12, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .glassButtonStyle()
        .circularButtonShape()
        .controlSize(.small)
        .accessibilityLabel(Strings.pause)
    }

    private var accessibilityValueText: String {
        switch phase {
        case .waitingForTap: return Strings.tapToLoad
        case .failed(let torUnavailable): return torUnavailable ? Strings.torUnavailable : Strings.loadFailed
        case .loading, .loaded: return ""
        }
    }

    private var accessibilityHintText: String {
        switch phase {
        case .waitingForTap, .failed: return Strings.loadHint
        case .loaded: return openMediaPreview == nil ? "" : Strings.openHint
        case .loading: return ""
        }
    }

    private var shouldLoadWithoutTap: Bool {
        GifLoadPolicy.loadsWithoutTap(
            isFromMe: isFromMe,
            isFavoriteSender: isFavoriteSender,
            autoRevealFavorites: autoRevealFavorites
        )
            // A tap on this message earlier in the session still counts
            // after the row was rebuilt by scrolling.
            || store.isRevealed(messageID: messageID)
    }

    private func handleTap() {
        switch phase {
        case .waitingForTap, .failed:
            load()
        case .loading:
            break
        case .loaded(let asset):
            openMediaPreview?(asset.fileURL)
        }
    }

    /// A GIF that showed (mine, or one I received and loaded) joins the
    /// picker's Recent tab. Only the link and shape are kept.
    private func rememberAsRecent(_ asset: GifAsset) {
        recents.record(link: link.url.absoluteString, aspectRatio: asset.aspectRatio, date: sentAt)
    }

    private func load() {
        phase = .loading
        store.markRevealed(messageID: messageID)
        let link = link
        let store = store
        Task { @MainActor in
            do {
                let asset = try await store.load(link)
                // The size first, then the frames: the row takes its final
                // height before anything plays in it.
                aspectRatio = Self.displayAspectRatio(asset.aspectRatio ?? aspectRatio)
                phase = .loaded(asset)
                rememberAsRecent(asset)
            } catch is CancellationError {
                // A wipe cancelled it; the row is about to go too.
                phase = .waitingForTap
            } catch {
                phase = .failed(torUnavailable: (error as? GifLoadError) == .torUnavailable)
            }
        }
    }
}
