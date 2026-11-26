//
// ImageDropTarget.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// macOS: accepts images dragged in from Finder, Photos or a browser and
    /// hands each one to `onDrop` as a file URL the app owns. No-op on iOS.
    func imageDropTarget(isEnabled: Bool, onDrop: @escaping (URL) -> Void) -> some View {
        #if os(macOS)
        modifier(ImageDropTargetModifier(isEnabled: isEnabled, onDrop: onDrop))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct ImageDropTargetModifier: ViewModifier {
    let isEnabled: Bool
    let onDrop: (URL) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            // An empty type list accepts nothing, so a disabled target
            // rejects drops without changing the view's identity.
            .onDrop(of: isEnabled ? [.image] : [], isTargeted: $isTargeted) { providers in
                let images = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
                guard isEnabled, !images.isEmpty else { return false }
                images.forEach(loadImage)
                return true
            }
            .overlay {
                if isTargeted && isEnabled {
                    dropHighlight
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private var dropHighlight: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
            Label {
                Text(String(localized: "content.drop.image_hint", defaultValue: "drop to send image", comment: "Hint shown while an image is dragged over the chat on macOS"))
            } icon: {
                Image(systemName: "photo.badge.plus")
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(in: Capsule())
        }
        .padding(8)
    }

    /// The provider's file exists only inside the callback, so copy it into
    /// a private folder first; image processing runs later on its own task.
    private func loadImage(from provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            guard let url, let copy = DroppedImageStore.keepCopy(of: url) else { return }
            DispatchQueue.main.async {
                onDrop(copy)
            }
        }
    }
}

/// Short-lived copies of dropped images. Old copies are deleted on the next
/// drop, so dropped pictures don't pile up in the app's temp folder.
enum DroppedImageStore {
    private static let maxAge: TimeInterval = 10 * 60

    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dropped-images", isDirectory: true)
    }

    /// Deletes every copy now. A dropped image is one the user just sent,
    /// so the message wipe takes these copies with the sent media.
    static func removeAll() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else { return }
        try? fileManager.removeItem(at: folder)
    }

    static func keepCopy(of url: URL) -> URL? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        removeStaleCopies()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try fileManager.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func removeStaleCopies() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
#endif
