//
// ChatBackgroundStore.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
//

import Foundation

enum ChatBackgroundOption: String, CaseIterable, Identifiable {
    case `default` = "default"
    case dusk = "dusk"
    case ocean = "ocean"
    case forest = "forest"
    case oled = "oled"

    var id: String { rawValue }
}

/// Persists a stable option ID for each conversation's ComposerDraftStore key.
struct ChatBackgroundStore {
    private let defaults: UserDefaults
    private let storageKey: String

    static let shared = ChatBackgroundStore(defaults: .standard)

    init(defaults: UserDefaults, storageKey: String = "chat.backgrounds") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func option(for conversation: ComposerDraftStore.Key) -> ChatBackgroundOption {
        let values = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        guard let id = values[conversation.storageString],
              let option = ChatBackgroundOption(rawValue: id) else { return .default }
        return option
    }

    func set(_ option: ChatBackgroundOption, for conversation: ComposerDraftStore.Key) {
        var values = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        if option == .default {
            values.removeValue(forKey: conversation.storageString)
        } else {
            values[conversation.storageString] = option.id
        }
        defaults.set(values, forKey: storageKey)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
    }
}
