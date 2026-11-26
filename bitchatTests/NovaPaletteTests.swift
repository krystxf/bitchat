//
// NovaPaletteTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
import Foundation
@testable import bitchat

/// Contrast of Nova's palette (WCAG 2), in light and dark mode.
struct NovaPaletteTests {
    private static let modes: [Bool] = [false, true]

    @Test(arguments: modes)
    func textReachesAAOnEveryBackdrop(isDark: Bool) {
        let primary: UInt32 = isDark ? 0xFFFFFF : 0x000000
        for backdrop in [NovaPalette.background, NovaPalette.surface, NovaPalette.surfaceRaised] {
            let fill = value(backdrop, isDark)
            #expect(contrast(primary, fill) >= 4.5)
            let secondary = value(NovaPalette.secondaryText, isDark)
            #expect(contrast(secondary, fill) >= 4.5, "\(hex(secondary)) on \(hex(fill))")
        }
    }

    @Test(arguments: modes)
    func accentReachesAAAsText(isDark: Bool) {
        let accent = value(NovaPalette.accent, isDark)
        // Dark-mode bubbles on the raised fill use their own link color.
        let backdrops = isDark
            ? [NovaPalette.background, NovaPalette.surface]
            : [NovaPalette.background, NovaPalette.surface, NovaPalette.surfaceRaised]
        for backdrop in backdrops {
            let fill = value(backdrop, isDark)
            #expect(contrast(accent, fill) >= 4.5, "\(hex(accent)) on \(hex(fill))")
        }
    }

    @Test func whiteOnAccentReachesAAInLightAndThreeToOneInDark() {
        #expect(contrast(0xFFFFFF, NovaPalette.accent.light) >= 4.5)
        #expect(contrast(0xFFFFFF, NovaPalette.accent.dark) >= 3)
    }

    @Test(arguments: modes)
    func highlightStandsOutFromTheBackdrop(isDark: Bool) {
        let highlight = value(NovaPalette.highlight, isDark)
        for backdrop in [NovaPalette.background, NovaPalette.surface] {
            #expect(contrast(highlight, value(backdrop, isDark)) >= 3)
        }
    }

    @Test(arguments: modes)
    func surfacesStepAwayFromTheBackground(isDark: Bool) {
        let background = value(NovaPalette.background, isDark)
        let surface = value(NovaPalette.surface, isDark)
        let raised = value(NovaPalette.surfaceRaised, isDark)
        #expect(contrast(surface, background) > 1.05)
        #expect(contrast(raised, background) > contrast(surface, background))
    }

    @Test func darkBackgroundIsCharcoalNotBlack() {
        #expect(luminance(NovaPalette.background.dark) > 0.01)
    }

    // MARK: - Helpers

    private func value(_ swatch: NovaPalette.Swatch, _ isDark: Bool) -> UInt32 {
        isDark ? swatch.dark : swatch.light
    }

    private func luminance(_ hex: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(hex >> 16) + 0.7152 * linear(hex >> 8) + 0.0722 * linear(hex)
    }

    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func hex(_ value: UInt32) -> String {
        String(format: "#%06X", value)
    }
}
