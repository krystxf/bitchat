//
// BLEIncomingFileStoreMediaWipeTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Testing
@testable import bitchat

/// `wipeAllMedia()` is extreme security mode's media deletion: every file
/// goes, the panic-recovery markers do not change, and one busy file cannot
/// shield the rest.
struct BLEIncomingFileStoreMediaWipeTests {
    private static let subdirectories = [
        "voicenotes/incoming",
        "voicenotes/outgoing",
        "images/incoming",
        "images/outgoing",
        "files/incoming",
        "files/outgoing"
    ]

    /// A fresh base directory holding one secret file per media directory
    /// plus one in a directory an older build used. Returns the file URLs.
    private func makeMediaTree(in base: URL) throws -> [URL] {
        let files = base.appendingPathComponent("files", isDirectory: true)
        var written: [URL] = []
        for subdirectory in Self.subdirectories + ["legacy"] {
            let directory = files.appendingPathComponent(subdirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("secret-\(written.count).bin")
            try Data("secret".utf8).write(to: file)
            written.append(file)
        }
        return written
    }

    private func makeBase(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func wipeAllMediaDeletesEveryFileAndKeepsTheTreeUsable() throws {
        let base = makeBase("media-wipe")
        defer { try? FileManager.default.removeItem(at: base) }
        let secrets = try makeMediaTree(in: base)
        let store = BLEIncomingFileStore(baseDirectory: base)

        try store.wipeAllMedia()

        for secret in secrets {
            #expect(!FileManager.default.fileExists(atPath: secret.path))
        }
        for subdirectory in Self.subdirectories {
            let directory = base
                .appendingPathComponent("files", isDirectory: true)
                .appendingPathComponent(subdirectory, isDirectory: true)
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    @Test func wipeAllMediaLeavesPanicRecoveryMarkersAlone() throws {
        // Not a panic: the next launch must not run the full wipe for it.
        let fresh = makeBase("media-wipe-no-marker")
        defer { try? FileManager.default.removeItem(at: fresh) }
        let freshStore = BLEIncomingFileStore(baseDirectory: fresh)
        try freshStore.wipeAllMedia()
        #expect(try !freshStore.isPanicRecoveryPending())

        // And a panic that is still pending stays pending.
        let pending = makeBase("media-wipe-pending-marker")
        defer { try? FileManager.default.removeItem(at: pending) }
        let pendingStore = BLEIncomingFileStore(baseDirectory: pending)
        try pendingStore.markPanicRecoveryPending()
        try pendingStore.wipeAllMedia()
        #expect(try pendingStore.isPanicRecoveryPending())
    }

    @Test func wipeAllMediaFallsBackToDeletingEntryByEntry() throws {
        let base = makeBase("media-wipe-fallback")
        defer { try? FileManager.default.removeItem(at: base) }
        let secrets = try makeMediaTree(in: base)
        let fileManager = SelectivelyFailingFileManager(
            failingDirectory: base.appendingPathComponent("files", isDirectory: true)
        )
        let store = BLEIncomingFileStore(fileManager: fileManager, baseDirectory: base)

        try store.wipeAllMedia()

        for secret in secrets {
            #expect(!FileManager.default.fileExists(atPath: secret.path))
        }
    }

    @Test func wipeAllMediaThrowsWhenAFileSurvivesButDeletesTheRest() throws {
        let base = makeBase("media-wipe-survivor")
        defer { try? FileManager.default.removeItem(at: base) }
        let secrets = try makeMediaTree(in: base)
        let survivor = secrets[2]
        let fileManager = SelectivelyFailingFileManager(
            failingDirectory: base.appendingPathComponent("files", isDirectory: true),
            undeletableFileName: survivor.lastPathComponent
        )
        let store = BLEIncomingFileStore(fileManager: fileManager, baseDirectory: base)

        #expect(throws: (any Error).self) {
            try store.wipeAllMedia()
        }

        #expect(FileManager.default.fileExists(atPath: survivor.path))
        for secret in secrets where secret != survivor {
            #expect(!FileManager.default.fileExists(atPath: secret.path))
        }
    }
}

/// Refuses to remove the `files` directory in one call, as a tree with a
/// busy entry can, and optionally refuses one file by name. Like a real
/// undeletable file, that file also blocks removing any directory that
/// still holds it.
private final class SelectivelyFailingFileManager: FileManager, @unchecked Sendable {
    private let failingDirectoryPath: String
    private let undeletableFileName: String?

    init(failingDirectory: URL, undeletableFileName: String? = nil) {
        self.failingDirectoryPath = failingDirectory.standardizedFileURL.path
        self.undeletableFileName = undeletableFileName
        super.init()
    }

    override func removeItem(at url: URL) throws {
        if url.standardizedFileURL.path == failingDirectoryPath
            || url.lastPathComponent == undeletableFileName
            || holdsUndeletableFile(url) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: url)
    }

    private func holdsUndeletableFile(_ directory: URL) -> Bool {
        guard let undeletableFileName,
              let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        while let entry = entries.nextObject() as? URL {
            if entry.lastPathComponent == undeletableFileName {
                return true
            }
        }
        return false
    }
}
