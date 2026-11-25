//
// ExtremeSecuritySettings.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Extreme security mode: delete every message as soon as the user leaves
/// the app.
///
/// A phone or laptop taken while the app sits in the background still holds
/// every conversation in memory and every image and voice note on disk. With
/// this mode on, leaving the app runs `ChatViewModel.wipeMessages()`, so
/// what someone finds afterwards is an empty timeline. Identity, contacts and
/// settings stay, so the app keeps working as before. Which moments count as
/// leaving the app is `ExtremeSecurityExitPolicy`'s decision.
///
/// Defaults to off: the mode throws away conversations for good, so it is
/// strictly the user's choice.
enum ExtremeSecuritySettings {
    private static let wipeMessagesOnExitKey = "security.extremeMode.wipeMessagesOnExit"

    static var isEnabled: Bool {
        get { isEnabled(in: .standard) }
        set { setEnabled(newValue, in: .standard) }
    }

    /// Store-injecting forms, so tests can assert the default and both settings
    /// without touching the shared preferences other tests read.
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: wipeMessagesOnExitKey) as? Bool ?? false
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: wipeMessagesOnExitKey)
    }

    /// Panic-wipe hook. Removing the key restores the off default, so a wiped
    /// device comes back like a fresh install.
    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: wipeMessagesOnExitKey)
    }
}
