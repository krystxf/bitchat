//
// ChatBackgroundStore.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
//

import Foundation
import CryptoKit
import ImageIO

enum ChatBackgroundOption: String, CaseIterable, Identifiable {
    case `default` = "default"
    case dusk = "dusk"
    case ocean = "ocean"
    case forest = "forest"
    case oled = "oled"
    case image = "image"

    var id: String { rawValue }
}

/// Persists a stable option ID for each conversation's ComposerDraftStore key.
struct ChatBackgroundStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private let images: ChatBackgroundImageStore

    static let shared = ChatBackgroundStore(defaults: .standard)

    init(defaults: UserDefaults, storageKey: String = "chat.backgrounds", images: ChatBackgroundImageStore = .shared) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.images = images
    }

    func option(for conversation: ComposerDraftStore.Key) -> ChatBackgroundOption {
        let values = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        guard let id = values[conversation.storageString],
              let option = ChatBackgroundOption(rawValue: id) else { return .default }
        if option == .image && !images.exists(for: conversation) { return .default }
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
        if option != .image { images.remove(for: conversation) }
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
        images.removeAll()
    }
}

/// Private, device-local image storage. Filenames are opaque hashes of the
/// conversation key; imported bytes are downsampled and re-encoded before save.
struct ChatBackgroundImageStore {
    static let shared = ChatBackgroundImageStore()
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatBackgrounds", isDirectory: true)
    }

    func fileURL(for conversation: ComposerDraftStore.Key) -> URL {
        let digest = SHA256.hash(data: Data(conversation.storageString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".jpg")
    }

    @discardableResult
    func save(_ data: Data, for conversation: ComposerDraftStore.Key, maxPixelSize: Int = 3000) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadUnknown)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(values)
        guard let destination = CGImageDestinationCreateWithURL(fileURL(for: conversation) as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        ChatBackgroundRasterCache.shared.clear()
        return fileURL(for: conversation)
    }

    func exists(for conversation: ComposerDraftStore.Key) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: conversation).path)
    }
    func remove(for conversation: ComposerDraftStore.Key) {
        try? FileManager.default.removeItem(at: fileURL(for: conversation))
        ChatBackgroundRasterCache.shared.clear()
    }
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        ChatBackgroundRasterCache.shared.clear()
    }
}
