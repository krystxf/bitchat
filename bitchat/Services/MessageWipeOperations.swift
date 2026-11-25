//
// MessageWipeOperations.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// The side effects of `ChatViewModel.wipeMessages()` that reach outside
/// the view model: files on disk, Notification Center, and caches shared by
/// the whole process.
///
/// Injectable like `PanicRecoveryOperations`, so tests can assert that each
/// one runs without deleting the host's real Application Support files,
/// touching its notifications, or emptying caches that parallel tests use.
struct MessageWipeOperations {
    /// Deletes every received and sent image, voice note and file, with
    /// their temporary copies. Throws when a file may remain. The panic wipe
    /// skips this one: it deletes the same tree inside its own recovery
    /// transaction.
    let deleteMediaFiles: () throws -> Void
    /// Deletes the persisted archive of carried public messages, which seeds
    /// the "heard here earlier" echoes on the next launch.
    let deletePublicArchive: () -> Void
    /// Removes delivered and queued notifications, which can quote messages.
    let removeNotifications: () -> Void
    /// Empties the decoded image thumbnails kept in memory, the GIF cache
    /// in memory and on disk (loads in flight are cancelled), and the GIF
    /// picker's Recent list.
    let clearMediaCaches: () -> Void

    static let live = MessageWipeOperations(
        deleteMediaFiles: {
            #if os(macOS)
            DroppedImageStore.removeAll()
            #endif
            try BLEIncomingFileStore().wipeAllMedia()
        },
        deletePublicArchive: { GossipMessageArchive.wipeDefault() },
        removeNotifications: { NotificationService.shared.removeAllNotifications() },
        clearMediaCaches: {
            ChatImageCache.removeAll()
            GifMediaStore.shared.removeAll()
            GifRecentsStore.shared.removeAll()
        }
    )

    /// No side effects outside the view model unless a test supplies them.
    static func ephemeral(
        deleteMediaFiles: @escaping () throws -> Void = {},
        deletePublicArchive: @escaping () -> Void = {},
        removeNotifications: @escaping () -> Void = {},
        clearMediaCaches: @escaping () -> Void = {}
    ) -> MessageWipeOperations {
        MessageWipeOperations(
            deleteMediaFiles: deleteMediaFiles,
            deletePublicArchive: deletePublicArchive,
            removeNotifications: removeNotifications,
            clearMediaCaches: clearMediaCaches
        )
    }
}
