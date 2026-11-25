//
// MediaRevealSettings.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Controls whether incoming images from favorite contacts skip the blur.
///
/// Every received image starts blurred until it is tapped, so an unexpected
/// picture never shows on screen by itself. People you marked as favorites
/// are people you chose to trust, so their images may show right away when
/// this is on. Images from everyone else stay blurred either way.
///
/// Defaults to off: revealing anything automatically is the user's choice.
enum MediaRevealSettings {
    /// UserDefaults key; views read it through `@AppStorage` so a change in
    /// settings applies to the next image that renders.
    static let autoRevealFavoritesKey = "media.autoRevealFavoriteImages"

    static var autoRevealFavorites: Bool {
        get { autoRevealFavorites(in: .standard) }
        set { setAutoRevealFavorites(newValue, in: .standard) }
    }

    /// Store-injecting forms, so tests can assert the default and both settings
    /// without touching the shared preferences other tests read.
    static func autoRevealFavorites(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: autoRevealFavoritesKey) as? Bool ?? false
    }

    static func setAutoRevealFavorites(_ reveal: Bool, in defaults: UserDefaults) {
        defaults.set(reveal, forKey: autoRevealFavoritesKey)
    }

    /// Panic-wipe hook. Removing the key restores the blurred default, so a
    /// wiped device cannot come back showing more than a fresh install.
    static func reset() {
        reset(in: .standard)
    }

    static func reset(in defaults: UserDefaults) {
        defaults.removeObject(forKey: autoRevealFavoritesKey)
    }
}
