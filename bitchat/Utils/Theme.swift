//
// Theme.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Semantic colors for the app's Liquid Glass look.
/// Views should consume these via `@ThemedPalette` rather than computing colors inline.
struct ThemePalette {
    /// Primary window/sheet background.
    let background: Color
    /// Primary text color.
    let primary: Color
    /// De-emphasized text (timestamps, hints, captions).
    let secondary: Color
    /// Interactive tint (buttons, toggles, selection).
    let accent: Color
    /// Location/geohash channel accent (badges, counts, subtitles).
    let locationAccent: Color
    /// Informational accent (links, read receipts, teleport markers).
    let accentBlue: Color
    /// Destructive/error accent.
    let alertRed: Color
    /// Hairline separators.
    let divider: Color

    static let liquidGlass = ThemePalette(
        background: systemBackground,
        primary: .primary,
        secondary: .secondary,
        accent: .blue,
        locationAccent: .green,
        accentBlue: .blue,
        alertRed: .red,
        divider: separator
    )

    private static var systemBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    private static var separator: Color {
        #if os(iOS)
        Color(UIColor.separator)
        #else
        Color(NSColor.separatorColor)
        #endif
    }
}

/// Resolves the app's color palette. The colors are dynamic system colors,
/// so they follow the view's color scheme on their own.
///
///     @ThemedPalette private var palette
///     var body: some View { Text("hi").foregroundColor(palette.primary) }
@propertyWrapper
struct ThemedPalette: DynamicProperty {
    var wrappedValue: ThemePalette { .liquidGlass }
}

// MARK: - Themed view helpers

/// Root backdrop: a subtle static gradient with a soft tinted glow. Glass
/// panels need visual texture behind them to refract, and collapse to flat
/// gray over a solid color.
struct ThemedRootBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.09, green: 0.10, blue: 0.15), Color(red: 0.04, green: 0.04, blue: 0.07)]
                    : [Color(red: 0.93, green: 0.95, blue: 1.0), Color(red: 0.98, green: 0.97, blue: 0.99)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.blue.opacity(isDark ? 0.22 : 0.12), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 600
            )
            RadialGradient(
                colors: [Color.purple.opacity(isDark ? 0.14 : 0.08), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 500
            )
        }
        // Full-bleed: passed to .background(_:) as a view, a backdrop stops
        // at the safe area. In a sheet, the sheet's own background would then
        // show through the home-indicator inset.
        .ignoresSafeArea()
    }
}

/// Conversation-specific backdrop. OLED mode is pure black in dark mode and
/// the system window background in light mode so foreground controls retain
/// their normal contrast.
struct ChatConversationBackground: View {
    let option: ChatBackgroundOption
    var conversationKey: ComposerDraftStore.Key? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if option == .image, let conversationKey, ChatBackgroundImageStore.shared.exists(for: conversationKey) {
                ChatBackgroundImageView(url: ChatBackgroundImageStore.shared.fileURL(for: conversationKey), isDark: isDark)
            } else if option == .default || option == .image {
                ThemedRootBackground()
            } else if option == .oled {
                (isDark ? Color.black : systemBackground).ignoresSafeArea()
            } else {
                ZStack {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    RadialGradient(
                        colors: [glowColor.opacity(isDark ? 0.22 : 0.12), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 600
                    )
                    RadialGradient(
                        colors: [secondaryGlow.opacity(isDark ? 0.14 : 0.08), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 500
                    )
                }
                .ignoresSafeArea()
            }
        }
    }

    private var gradientColors: [Color] {
        switch option {
        case .default, .oled, .image: []
        case .dusk:
            isDark
                ? [Color(red: 0.13, green: 0.09, blue: 0.16), Color(red: 0.05, green: 0.04, blue: 0.08)]
                : [Color(red: 0.97, green: 0.92, blue: 0.97), Color(red: 0.99, green: 0.96, blue: 0.97)]
        case .ocean:
            isDark
                ? [Color(red: 0.06, green: 0.12, blue: 0.17), Color(red: 0.03, green: 0.05, blue: 0.09)]
                : [Color(red: 0.88, green: 0.95, blue: 0.98), Color(red: 0.96, green: 0.98, blue: 0.99)]
        case .forest:
            isDark
                ? [Color(red: 0.07, green: 0.13, blue: 0.12), Color(red: 0.03, green: 0.06, blue: 0.06)]
                : [Color(red: 0.90, green: 0.96, blue: 0.92), Color(red: 0.97, green: 0.99, blue: 0.97)]
        }
    }

    private var glowColor: Color {
        switch option {
        case .dusk: .purple
        case .ocean: .cyan
        case .forest: .green
        case .default, .oled, .image: .blue
        }
    }

    private var secondaryGlow: Color {
        switch option {
        case .dusk: .pink
        case .ocean: .blue
        case .forest: .mint
        case .default, .oled, .image: .purple
        }
    }

    private var systemBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}

private struct ChatBackgroundImageView: View {
    let url: URL
    let isDark: Bool
    @State private var image: Image?
    /// Bumped when a new image replaces the old one at the same URL.
    @State private var revision = 0
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    image.resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else { Color.black }
                (isDark ? Color.black.opacity(0.34) : Color.white.opacity(0.42))
                (isDark ? Color.black.opacity(0.12) : Color.white.opacity(0.08)).blur(radius: 10)
            }
            .ignoresSafeArea()
            .task(id: ChatBackgroundImageLoadID(url: url, revision: revision)) {
                image = await Task.detached(priority: .utility) { ChatBackgroundRasterCache.shared.image(at: url) }.value
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatBackgroundImageDidChange)) { _ in
                revision &+= 1
            }
        }
    }
}

/// What a background image view loads: the file, and how many times it was
/// replaced since the view appeared.
struct ChatBackgroundImageLoadID: Hashable {
    let url: URL
    let revision: Int
}

/// Decoded rasters are shared by the full-screen backdrop and picker thumbnail.
final class ChatBackgroundRasterCache {
    static let shared = ChatBackgroundRasterCache()
    #if os(iOS)
    private let images = NSCache<NSString, UIImage>()
    #else
    private let images = NSCache<NSString, NSImage>()
    #endif

    func clear() { images.removeAllObjects() }

    func image(at url: URL) -> Image? {
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = "\(url.path):\(stamp)" as NSString
        #if os(iOS)
        if let cached = images.object(forKey: key) { return Image(uiImage: cached) }
        guard let data = try? Data(contentsOf: url), let decoded = UIImage(data: data) else { return nil }
        images.setObject(decoded, forKey: key)
        return Image(uiImage: decoded)
        #else
        if let cached = images.object(forKey: key) { return Image(nsImage: cached) }
        guard let data = try? Data(contentsOf: url), let decoded = NSImage(data: data) else { return nil }
        images.setObject(decoded, forKey: key)
        return Image(nsImage: decoded)
        #endif
    }
}

/// Wraps glass-shape content in real Liquid Glass on OS 26+, with a material
/// fallback below that keeps the frosted look.
private struct GlassPanel<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            materialFallback(content)
        }
        #else
        materialFallback(content)
        #endif
    }

    private func materialFallback(_ content: Content) -> some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }
}

extension View {
    func bitchatFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.bitchatSystem(size: size, weight: weight))
    }

    /// Chrome surface for the header: floats the content as an inset Liquid
    /// Glass panel (content is expected to scroll underneath via safe-area
    /// insets).
    func themedChromePanel(edge: VerticalEdge) -> some View {
        modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
            .padding(.horizontal, 8)
            .padding(edge == .top ? .top : .bottom, 4)
    }

    /// Liquid Glass in an arbitrary shape, for standalone controls such as
    /// the composer's input capsule and attachment button.
    func glassSurface<S: Shape>(in shape: S) -> some View {
        modifier(GlassPanel(shape: shape))
    }

    /// Floating surface for popover-style boxes (autocomplete, command
    /// suggestions).
    func themedOverlayPanel() -> some View {
        modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
    }
}
