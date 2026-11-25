import XCTest
import ImageIO
@testable import bitchat

final class ChatBackgroundStoreTests: XCTestCase {
    private func makeStore() -> (ChatBackgroundStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return (ChatBackgroundStore(defaults: defaults), defaults)
    }

    func testRoundTripsOptionsPerConversation() {
        let (store, _) = makeStore()
        let mesh = ComposerDraftStore.Key.mesh
        let dm = ComposerDraftStore.Key.privateChat(stableID: "fingerprint")

        store.set(.ocean, for: mesh)
        store.set(.forest, for: dm)

        XCTAssertEqual(store.option(for: mesh), .ocean)
        XCTAssertEqual(store.option(for: dm), .forest)
    }

    func testMissingChoiceUsesDefault() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.option(for: .mesh), .default)
    }

    func testUnknownSavedIDFallsBackToDefault() {
        let (store, defaults) = makeStore()
        defaults.set(["mesh": "future-option"], forKey: "chat.backgrounds")
        XCTAssertEqual(store.option(for: .mesh), .default)
    }

    func testResetClearsChoices() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = ChatBackgroundImageStore(directory: directory)
        let (defaultStore, defaults) = makeStore()
        let store = ChatBackgroundStore(defaults: defaults, images: images)
        _ = try? images.save(testImageData(), for: .mesh)
        store.set(.image, for: .mesh)
        store.reset()
        XCTAssertEqual(store.option(for: .mesh), .default)
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.fileURL(for: .mesh).path))
        _ = defaultStore
    }

    func testImageOptionRoundTripsAndMissingFileFallsBack() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = ChatBackgroundImageStore(directory: temp)
        let (defaultsStore, defaults) = makeStore()
        let store = ChatBackgroundStore(defaults: defaults, images: images)
        try images.save(testImageData(), for: .mesh)
        store.set(.image, for: .mesh)
        XCTAssertEqual(store.option(for: .mesh), .image)
        images.remove(for: .mesh)
        XCTAssertEqual(store.option(for: .mesh), .default)
        _ = defaultsStore
    }

    func testImageFileNameIsOpaqueAndReplaceUsesSamePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = ChatBackgroundImageStore(directory: directory)
        let first = try images.save(testImageData(), for: .mesh)
        let second = try images.save(testImageData(), for: .mesh)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.lastPathComponent.contains("mesh"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        images.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
    }

    func testChoosingAnotherOptionDeletesCustomImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = ChatBackgroundImageStore(directory: directory)
        let (defaultStore, defaults) = makeStore()
        let store = ChatBackgroundStore(defaults: defaults, images: images)
        let file = try images.save(testImageData(), for: .mesh)
        store.set(.image, for: .mesh)
        store.set(.ocean, for: .mesh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.option(for: .mesh), .ocean)
        _ = defaultStore
    }

    private func testImageData() -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 128, 255, 255]
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
