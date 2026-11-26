//
// Theme.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Nova palette

/// Nova's colors: warm neutrals with one vivid blue. Each swatch has a light
/// and a dark value; `Color` resolves them per color scheme (see the
/// `ShapeStyle` tokens below).
///
/// Contrast (WCAG 2, checked by `NovaPaletteTests`):
/// - `secondaryText` and `accent` reach AA (4.5:1) as text on `background`,
///   `surface` and `surfaceRaised`, except `accent` on `surfaceRaised` in
///   dark mode; bubbles use their own link color there.
/// - White on `accent` reaches AA in light mode. In dark mode it reaches
///   3:1, which suits icons and bold labels, as the system blue does.
enum NovaPalette {
    struct Swatch: Equatable {
        let light: UInt32
        let dark: UInt32
    }

    /// The window and list backdrop: warm off-white, soft charcoal.
    static let background = Swatch(light: 0xFBF9F4, dark: 0x1F2022)
    /// Cards and grouped rows: cream, warm gray.
    static let surface = Swatch(light: 0xF5F0E4, dark: 0x2A2B30)
    /// Fills on a surface: chips, pills, other people's bubbles.
    static let surfaceRaised = Swatch(light: 0xEDE5D2, dark: 0x3C3E43)
    /// Separators and chip borders: soft beige, subtle gray.
    static let hairline = Swatch(light: 0xE4DBC7, dark: 0x3A3C41)
    /// De-emphasized text: warm gray, light gray.
    static let secondaryText = Swatch(light: 0x6A665D, dark: 0xA8AEB3)
    /// Primary actions, links and selection: a vivid blue.
    static let accent = Swatch(light: 0x0062D1, dark: 0x3796FF)
    /// Small highlights such as unread dots and badges: gold.
    static let highlight = Swatch(light: 0xB07A00, dark: 0xFBD740)
}

extension ShapeStyle where Self == Color {
    /// Window and list backdrop (`NovaPalette.background`).
    static var novaBackground: Color { Color(NovaPalette.background) }
    /// Cards and grouped rows (`NovaPalette.surface`).
    static var novaSurface: Color { Color(NovaPalette.surface) }
    /// Chips, pills and other people's bubbles (`NovaPalette.surfaceRaised`).
    static var novaSurfaceRaised: Color { Color(NovaPalette.surfaceRaised) }
    /// Separators and chip borders (`NovaPalette.hairline`).
    static var novaHairline: Color { Color(NovaPalette.hairline) }
    /// De-emphasized text (`NovaPalette.secondaryText`).
    static var novaSecondaryText: Color { Color(NovaPalette.secondaryText) }
    /// Primary actions and links (`NovaPalette.accent`). It is also the
    /// app's tint (the `AccentColor` asset).
    static var novaAccent: Color { Color(NovaPalette.accent) }
    /// Unread dots and badges (`NovaPalette.highlight`).
    static var novaHighlight: Color { Color(NovaPalette.highlight) }
}

extension Color {
    /// A dynamic color: the swatch's light or dark value, by the color
    /// scheme of the view that draws it.
    init(_ swatch: NovaPalette.Swatch) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(novaHex: traits.userInterfaceStyle == .dark ? swatch.dark : swatch.light)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(novaHex: isDark ? swatch.dark : swatch.light)
        })
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(novaHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#else
private extension NSColor {
    convenience init(novaHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

extension View {
    /// Nova's backdrop behind a List or Form: hides the system's grouped
    /// gray so `novaBackground` shows. Give rows `novaSurface` with
    /// `.listRowBackground(Color.novaSurface)`.
    func novaListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.novaBackground.ignoresSafeArea())
    }
}

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
        background: .novaBackground,
        primary: .primary,
        secondary: .novaSecondaryText,
        accent: .novaAccent,
        locationAccent: .green,
        accentBlue: .novaAccent,
        alertRed: .red,
        divider: .novaHairline
    )
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

/// Root backdrop: Nova's flat warm background, full-bleed. Liquid Glass
/// controls float over it, as they float over the plain backdrop in
/// Messages.
struct ThemedRootBackground: View {
    var body: some View {
        // Full-bleed: passed to .background(_:) as a view, a backdrop stops
        // at the safe area. In a sheet, the sheet's own background would then
        // show through the home-indicator inset.
        Color.novaBackground
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
        // A clear frame that ignores every safe area (bars, home indicator,
        // keyboard) sets the size, and the photo fills it. A GeometryReader
        // here measured only the safe area, so the photo was framed smaller
        // than the screen and the edges showed through.
        Color.clear
            .overlay {
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    Color.black
                }
            }
            .clipped()
            .overlay {
                ZStack {
                    (isDark ? Color.black.opacity(0.34) : Color.white.opacity(0.42))
                    (isDark ? Color.black.opacity(0.12) : Color.white.opacity(0.08)).blur(radius: 10)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task(id: ChatBackgroundImageLoadID(url: url, revision: revision)) {
                image = await Task.detached(priority: .utility) { ChatBackgroundRasterCache.shared.image(at: url) }.value
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatBackgroundImageDidChange)) { _ in
                revision &+= 1
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
