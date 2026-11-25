import Foundation

/// The app follows the language chosen for it in the system settings (iOS
/// Settings > Nova Chat > Language, macOS System Settings > General >
/// Language & Region > Applications). An older build had its own in-app
/// language picker; this clears what that picker stored, once, so the
/// system setting is in charge again.
enum AppLanguageSettings {
    /// Where the removed in-app picker kept its choice.
    private static let legacyOverrideKey = "app.languageOverride"
    private static let appleLanguagesKey = "AppleLanguages"

    /// Removes an override written by the old in-app picker. It only touches
    /// AppleLanguages when that picker wrote it, so a language chosen in the
    /// system settings stays as it is.
    static func clearLegacyOverride(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: legacyOverrideKey) != nil else { return }
        defaults.removeObject(forKey: legacyOverrideKey)
        defaults.removeObject(forKey: appleLanguagesKey)
    }
}
