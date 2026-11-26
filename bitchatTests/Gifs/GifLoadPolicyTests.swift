//
// GifLoadPolicyTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Testing
@testable import bitchat

@Suite("GIF load policy")
struct GifLoadPolicyTests {
    @Test func myOwnGifsLoadByThemselves() {
        #expect(GifLoadPolicy.loadsWithoutTap(isFromMe: true, isFavoriteSender: false, autoRevealFavorites: false))
    }

    @Test func favoritesLoadOnlyWithTheSettingOn() {
        #expect(GifLoadPolicy.loadsWithoutTap(isFromMe: false, isFavoriteSender: true, autoRevealFavorites: true))
        #expect(!GifLoadPolicy.loadsWithoutTap(isFromMe: false, isFavoriteSender: true, autoRevealFavorites: false))
    }

    @Test func everyoneElseWaitsForATap() {
        #expect(!GifLoadPolicy.loadsWithoutTap(isFromMe: false, isFavoriteSender: false, autoRevealFavorites: true))
        #expect(!GifLoadPolicy.loadsWithoutTap(isFromMe: false, isFavoriteSender: false, autoRevealFavorites: false))
    }

    @Test func unknownSizesUseTheDefaultShape() {
        #expect(GifMessageView.displayAspectRatio(nil) == GifMessageView.defaultAspectRatio)
        #expect(GifMessageView.displayAspectRatio(0) == GifMessageView.defaultAspectRatio)
        #expect(GifMessageView.displayAspectRatio(.infinity) == GifMessageView.defaultAspectRatio)
    }

    @Test func extremeShapesAreClamped() {
        #expect(GifMessageView.displayAspectRatio(1.5) == 1.5)
        #expect(GifMessageView.displayAspectRatio(0.1) == 0.5)
        #expect(GifMessageView.displayAspectRatio(10) == 2.5)
    }
}
