import XCTest
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
        let (store, _) = makeStore()
        store.set(.dusk, for: .mesh)
        store.reset()
        XCTAssertEqual(store.option(for: .mesh), .default)
    }
}
