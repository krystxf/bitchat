import CoreGraphics
import SwiftUI
import Testing
@testable import bitchat

/// The window backdrop has to cover the safe-area insets too. If it stops at
/// the safe area, the window's own background shows through the
/// home-indicator inset as a flat band under the gradient.
@Suite("ThemedRootBackground")
@MainActor
struct ThemedRootBackgroundTests {
    @Test(arguments: ColorScheme.allCases)
    func backdrop_fillsBottomSafeAreaInset(colorScheme: ColorScheme) throws {
        // A SwiftUI safe-area inset stands in for the home indicator: it
        // reserves the bottom 20 pt, the way the window's bottom inset does.
        let view = Color.clear
            .background(ThemedRootBackground())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 20)
            }
            .frame(width: 40, height: 100)
            .environment(\.colorScheme, colorScheme)

        let image = try RenderedPixels(view)
        // Sanity check: the backdrop renders inside the safe area.
        #expect(image.alpha(x: 20, y: 40) == 255)
        // Regression: the backdrop also covers the inset.
        #expect(image.alpha(x: 20, y: 90) == 255)
    }
}

/// RGBA8 pixels of a view rendered offscreen at 1x.
@MainActor
private struct RenderedPixels {
    private let width: Int
    private let bytes: [UInt8]

    init(_ view: some View) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        width = image.width
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        bytes = buffer
    }

    /// Alpha at (x, y), with y measured from the top edge.
    func alpha(x: Int, y: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + 3]
    }
}

struct ChatBackgroundResolutionTests {
    @Test func ownChoiceWins() {
        #expect(ChatBackgroundOption.resolved(choice: .ocean, imageExists: false, defaultRawValue: "dusk") == .ocean)
        #expect(ChatBackgroundOption.resolved(choice: .image, imageExists: true, defaultRawValue: "dusk") == .image)
    }

    @Test func defaultFollowsSettings() {
        #expect(ChatBackgroundOption.resolved(choice: .default, imageExists: false, defaultRawValue: "forest") == .forest)
        #expect(ChatBackgroundOption.resolved(choice: .default, imageExists: false, defaultRawValue: "bogus") == .default)
    }

    @Test func missingImageFallsBackToSettings() {
        #expect(ChatBackgroundOption.resolved(choice: .image, imageExists: false, defaultRawValue: "oled") == .oled)
    }

    @Test func settingsDefaultIsNeverAnImage() {
        #expect(ChatBackgroundOption.resolved(choice: .default, imageExists: true, defaultRawValue: "image") == .default)
    }

    @Test func savingAndRemovingAnImageAnnouncesTheChange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-background-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatBackgroundImageStore(directory: directory)
        let key = ComposerDraftStore.Key.mesh
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))

        let announcements = AnnouncementCounter()
        let observer = NotificationCenter.default.addObserver(forName: .chatBackgroundImageDidChange, object: nil, queue: nil) { _ in
            announcements.count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Other tests running in parallel can post too, so each step checks
        // that the count grew rather than an exact total.
        try await MainActor.run { _ = try store.save(png, for: key) }
        #expect(store.exists(for: key))
        let afterSave = announcements.count
        #expect(afterSave >= 1)
        await MainActor.run { store.remove(for: key) }
        #expect(!store.exists(for: key))
        #expect(announcements.count > afterSave)
    }
}

/// Posts can come from other tests on other threads, so the count is locked.
private final class AnnouncementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
