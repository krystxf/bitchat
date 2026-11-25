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

    /// Floating surface for popover-style boxes (autocomplete, command
    /// suggestions).
    func themedOverlayPanel() -> some View {
        modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
    }

    /// Root background for sheets — same backdrop as the main window so every
    /// surface speaks one visual language.
    func themedSheetBackground() -> some View {
        background(ThemedRootBackground())
    }
}
