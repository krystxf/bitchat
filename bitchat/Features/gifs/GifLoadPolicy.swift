//
// GifLoadPolicy.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// When a GIF may load without a tap.
///
/// Loading a GIF tells Giphy or Tenor the device's IP address (unless Tor
/// carries it). So a GIF loads by itself only when I sent it, or when a
/// favorite sent it and "show images from favorites" is on: the same people
/// whose images skip the blur. Every other GIF waits for a tap, and nothing
/// is fetched before it, not even the page.
enum GifLoadPolicy {
    static func loadsWithoutTap(isFromMe: Bool, isFavoriteSender: Bool, autoRevealFavorites: Bool) -> Bool {
        isFromMe || (autoRevealFavorites && isFavoriteSender)
    }
}
