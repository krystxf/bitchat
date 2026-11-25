//
// GifMediaStore.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import AVFoundation
import BitLogger
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// A GIF's media file in the cache.
struct GifAsset: Equatable, Sendable {
    let fileURL: URL
    let format: GifMediaFormat
    /// Width / height as the file plays. Nil when neither the file nor the
    /// page said.
    let aspectRatio: CGFloat?
}

/// Loads GIFs once and keeps them: in memory for this session, and on disk
/// in a cache folder that backups skip.
///
/// Both message wipes (panic and extreme security mode's exit wipe) call
/// `removeAll()`, which cancels loads in flight, forgets what was revealed
/// and deletes the folder. A load that started before a wipe never writes
/// after it: each load carries the generation it started in.
final class GifMediaStore: @unchecked Sendable {
    static let shared = GifMediaStore(
        directory: GifMediaStore.defaultDirectory(),
        resolver: GifResolver(fetcher: GifNetworkFetcher.live)
    )

    /// The folder is pruned, oldest first, when it grows past this.
    static let maxDiskBytes = 64 * 1_048_576
    static let pruneTargetBytes = 48 * 1_048_576
    /// The longest MP4 the chat plays. GIF services keep clips far shorter.
    static let maxVideoSeconds: Double = 90
    /// The largest frame either format may claim, in pixels.
    static let maxPixelArea: Double = 4096 * 4096

    private let directory: URL?
    private let resolver: GifResolver
    private let fileManager: FileManager
    private let lock = NSLock()
    private var assets: [String: GifAsset] = [:]
    /// Keys known to have no file on disk, so a row's repeated renders do
    /// not each look for one.
    private var missingOnDisk: Set<String> = []
    private var inFlight: [String: (id: UUID, task: Task<GifAsset, Error>)] = [:]
    private var revealedMessageIDs: Set<String> = []
    private var generation = 0

    init(directory: URL?, resolver: GifResolver, fileManager: FileManager = .default) {
        self.directory = directory
        self.resolver = resolver
        self.fileManager = fileManager
    }

    /// Caches/<bundle ID>/gif-cache. The app's Caches folder is its own on
    /// iOS and in the macOS sandbox; the bundle folder keeps an unsandboxed
    /// build from sharing one with anything else.
    static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "bitchat", isDirectory: true)
            .appendingPathComponent("gif-cache", isDirectory: true)
    }

    // MARK: - Reveal state

    /// Whether the person tapped this message's GIF to load it during this
    /// session. Rows are rebuilt as they scroll, so the tap is kept here.
    func isRevealed(messageID: String) -> Bool {
        lock.withLock { revealedMessageIDs.contains(messageID) }
    }

    func markRevealed(messageID: String) {
        lock.withLock { _ = revealedMessageIDs.insert(messageID) }
    }

    // MARK: - Lookup

    /// The cached asset for a link, from memory or disk, without any
    /// network. Cheap enough for a view's initializer.
    func cachedAsset(for link: GifLink) -> GifAsset? {
        let key = link.cacheKey
        let known: (asset: GifAsset?, isMissing: Bool) = lock.withLock {
            (assets[key], missingOnDisk.contains(key))
        }
        if let asset = known.asset { return asset }
        if known.isMissing { return nil }
        let generation = lock.withLock { self.generation }
        let asset = readRecord(for: key)
        lock.withLock {
            guard self.generation == generation else { return }
            if let asset {
                assets[key] = asset
            } else {
                missingOnDisk.insert(key)
            }
        }
        return asset
    }

    /// The asset whose file this is, when the file is in the cache. The
    /// image preview uses it to play a GIF it was handed by file.
    func asset(forFileURL url: URL) -> GifAsset? {
        guard let directory,
              url.standardizedFileURL.deletingLastPathComponent().path == directory.standardizedFileURL.path
        else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        if let asset = lock.withLock({ assets.values.first { $0.fileURL.lastPathComponent == url.lastPathComponent } }) {
            return asset
        }
        return readRecord(named: name)
    }

    // MARK: - Loading

    /// The GIF's media: from the cache, from a load already running for the
    /// same link, or from the network.
    func load(_ link: GifLink) async throws -> GifAsset {
        if let asset = cachedAsset(for: link) { return asset }
        let key = link.cacheKey
        let (id, task): (UUID, Task<GifAsset, Error>) = lock.withLock {
            if let running = inFlight[key] { return running }
            let generation = self.generation
            let id = UUID()
            let task = Task { [resolver] in
                let media = try await resolver.media(for: link)
                return try await self.store(media, key: key, generation: generation)
            }
            inFlight[key] = (id, task)
            return (id, task)
        }
        defer {
            lock.withLock {
                if inFlight[key]?.id == id { inFlight[key] = nil }
            }
        }
        return try await task.value
    }

    /// Empties memory and disk, cancels loads in flight, and forgets which
    /// GIFs were revealed.
    func removeAll() {
        let tasks: [Task<GifAsset, Error>] = lock.withLock {
            generation += 1
            let tasks = inFlight.values.map(\.task)
            inFlight.removeAll()
            assets.removeAll()
            missingOnDisk.removeAll()
            revealedMessageIDs.removeAll()
            return tasks
        }
        tasks.forEach { $0.cancel() }
        GifFrameCache.removeAll()
        guard let directory else { return }
        do {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        } catch {
            SecureLogger.error("GIF cache could not be deleted: \(error)", category: .security)
        }
    }

    // MARK: - Disk

    private struct Record: Codable {
        let format: GifMediaFormat
        let width: Double?
        let height: Double?
    }

    /// File names are a hash of the key, so the folder does not list the
    /// links that were viewed.
    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func readRecord(for key: String) -> GifAsset? {
        readRecord(named: Self.fileName(for: key))
    }

    private func readRecord(named name: String) -> GifAsset? {
        guard let directory else { return nil }
        let recordURL = directory.appendingPathComponent(name).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return nil }
        let fileURL = directory.appendingPathComponent(name).appendingPathExtension(record.format.fileExtension)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return GifAsset(
            fileURL: fileURL,
            format: record.format,
            aspectRatio: Self.aspectRatio(width: record.width, height: record.height)
        )
    }

    /// Checks the media decodes within limits, writes it with its record,
    /// and returns the asset, unless a wipe ran since the load started.
    private func store(_ media: GifDownloadedMedia, key: String, generation: Int) async throws -> GifAsset {
        guard let directory else { throw GifLoadError.undecodable }
        try Task.checkCancellation()
        try prepareDirectory(directory)
        let name = Self.fileName(for: key)
        let fileURL = directory.appendingPathComponent(name).appendingPathExtension(media.format.fileExtension)
        let recordURL = directory.appendingPathComponent(name).appendingPathExtension("json")

        try writeIfCurrent(media.data, to: fileURL, generation: generation)
        let size: CGSize
        do {
            size = try await Self.validatedPixelSize(of: fileURL, format: media.format, data: media.data)
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
        let pixelSize = size.width > 0 ? size : (media.pixelSize ?? .zero)
        let record = Record(
            format: media.format,
            width: pixelSize.width > 0 ? Double(pixelSize.width) : nil,
            height: pixelSize.height > 0 ? Double(pixelSize.height) : nil
        )
        try writeIfCurrent(try JSONEncoder().encode(record), to: recordURL, generation: generation)

        let asset = GifAsset(
            fileURL: fileURL,
            format: media.format,
            aspectRatio: Self.aspectRatio(width: record.width, height: record.height)
        )
        let isCurrent: Bool = lock.withLock {
            guard self.generation == generation else { return false }
            assets[key] = asset
            missingOnDisk.remove(key)
            return true
        }
        guard isCurrent else {
            // A wipe ran while this load finished: leave nothing behind.
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: recordURL)
            throw CancellationError()
        }
        prune(directory, keeping: [fileURL, recordURL])
        return asset
    }

    private func writeIfCurrent(_ data: Data, to url: URL, generation: Int) throws {
        guard lock.withLock({ self.generation == generation }) else { throw CancellationError() }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private func prepareDirectory(_ directory: URL) throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: BLEIncomingFileStore.mediaProtectionAttributes
        )
        // Caches are already outside iCloud and iTunes backups on iOS; mark
        // the folder anyway, which also keeps it out of Time Machine.
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Deletes the oldest entries once the folder passes its cap.
    private func prune(_ directory: URL, keeping kept: Set<URL>) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }
        var entries = files.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            return (url, values.contentModificationDate ?? .distantPast, size)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > Self.maxDiskBytes else { return }
        entries.sort { $0.date < $1.date }
        var removedNames: Set<String> = []
        for entry in entries where total > Self.pruneTargetBytes && !kept.contains(entry.url) {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            removedNames.insert(entry.url.deletingPathExtension().lastPathComponent)
        }
        guard !removedNames.isEmpty else { return }
        // An entry is its file and its record; drop any half left behind.
        for entry in entries where removedNames.contains(entry.url.deletingPathExtension().lastPathComponent) {
            try? fileManager.removeItem(at: entry.url)
        }
        lock.withLock {
            assets = assets.filter { !removedNames.contains($0.value.fileURL.deletingPathExtension().lastPathComponent) }
        }
    }

    // MARK: - Validation

    /// The file's own pixel size, after checking it decodes within limits.
    static func validatedPixelSize(of fileURL: URL, format: GifMediaFormat, data: Data) async throws -> CGSize {
        switch format {
        case .gif, .webp:
            guard let size = GifFrameDecoder.pixelSize(of: data),
                  Double(size.width * size.height) <= maxPixelArea
            else { throw GifLoadError.undecodable }
            return size
        case .mp4:
            let asset = AVURLAsset(url: fileURL)
            let duration: CMTime
            let tracks: [AVAssetTrack]
            do {
                duration = try await asset.load(.duration)
                tracks = try await asset.loadTracks(withMediaType: .video)
            } catch {
                throw GifLoadError.undecodable
            }
            guard let track = tracks.first,
                  duration.seconds.isFinite,
                  duration.seconds <= maxVideoSeconds
            else { throw GifLoadError.undecodable }
            let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let shown = naturalSize.applying(transform)
            let size = CGSize(width: abs(shown.width), height: abs(shown.height))
            guard Double(size.width * size.height) <= maxPixelArea else { throw GifLoadError.undecodable }
            return size
        }
    }

    static func aspectRatio(width: Double?, height: Double?) -> CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width / height)
    }
}
