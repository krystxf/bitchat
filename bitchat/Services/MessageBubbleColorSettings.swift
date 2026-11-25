//
// MessageBubbleColorSettings.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
//

import Foundation
import SwiftUI

enum MessageBubbleColor: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, green, teal, graphite, indigo, gold

    var id: String { rawValue }

    /// Dark saturated fills keep white message text readable in both color schemes.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .blue: (0.00, 0.38, 0.78)
        case .purple: (0.39, 0.20, 0.70)
        case .pink: (0.72, 0.09, 0.32)
        case .red: (0.72, 0.12, 0.12)
        case .orange: (0.65, 0.25, 0.00)
        case .green: (0.09, 0.43, 0.20)
        case .teal: (0.00, 0.40, 0.36)
        case .graphite: (0.29, 0.33, 0.39)
        case .indigo: (0.25, 0.32, 0.71)
        case .gold: (0.51, 0.36, 0.00)
        }
    }

    var color: Color {
        let value = rgb
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: 1)
    }

    /// WCAG 2.1 contrast ratio against white.
    var whiteContrastRatio: Double {
        let value = rgb
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(value.red) + 0.7152 * linear(value.green) + 0.0722 * linear(value.blue)
        return 1.05 / (luminance + 0.05)
    }
}

enum MessageBubbleColorSettings {
    static let key = "appearance.messageBubbleColor"
    static let migrationKey = "appearance.messageBubbleColor.migratedToDefault"

    static var selected: MessageBubbleColor {
        get { selected(in: .standard) }
        set { set(newValue, in: .standard) }
    }

    static func selected(in defaults: UserDefaults) -> MessageBubbleColor {
        migrateLegacySelection(in: defaults)
        guard let rawValue = defaults.string(forKey: key),
              let value = MessageBubbleColor(rawValue: rawValue) else { return .blue }
        return value
    }

    static func migrateLegacySelection(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        // The old key already stores the app-wide selection. Preserve it as
        // the default before conversation-specific colors are introduced.
        defaults.set(true, forKey: migrationKey)
    }

    static func set(_ color: MessageBubbleColor, in defaults: UserDefaults) {
        defaults.set(color.rawValue, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.set(true, forKey: migrationKey)
    }
}

private struct ResolvedMessageBubbleColorKey: EnvironmentKey {
    static let defaultValue = MessageBubbleColor.blue
}

extension EnvironmentValues {
    var resolvedMessageBubbleColor: MessageBubbleColor {
        get { self[ResolvedMessageBubbleColorKey.self] }
        set { self[ResolvedMessageBubbleColorKey.self] = newValue }
    }
}

/// Device-local color overrides indexed by the same stable keys as drafts
/// and chat backgrounds.
struct ConversationMessageColorStore {
    private let defaults: UserDefaults
    private let storageKey: String
    static let shared = ConversationMessageColorStore(defaults: .standard)

    init(defaults: UserDefaults, storageKey: String = "chat.messageColors") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func override(for conversation: ComposerDraftStore.Key) -> MessageBubbleColor? {
        guard let raw = (defaults.dictionary(forKey: storageKey) as? [String: String])?[conversation.storageString] else { return nil }
        return MessageBubbleColor(rawValue: raw)
    }

    func resolvedColor(for conversation: ComposerDraftStore.Key) -> MessageBubbleColor {
        override(for: conversation) ?? MessageBubbleColorSettings.selected(in: defaults)
    }

    func set(_ color: MessageBubbleColor?, for conversation: ComposerDraftStore.Key) {
        var values = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        if let color { values[conversation.storageString] = color.rawValue }
        else { values.removeValue(forKey: conversation.storageString) }
        defaults.set(values, forKey: storageKey)
        NotificationCenter.default.post(name: .conversationMessageColorChanged, object: conversation.storageString)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .conversationMessageColorChanged, object: nil)
    }
}

extension Notification.Name {
    static let conversationMessageColorChanged = Notification.Name("conversationMessageColorChanged")
}
