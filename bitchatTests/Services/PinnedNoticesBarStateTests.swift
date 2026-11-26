import Foundation
import Testing
@testable import bitchat

struct PinnedNoticesBarStateTests {
    private func post(_ id: UInt8, scope: String, createdAt: UInt64, content: String) -> BoardPostPacket {
        BoardPostPacket(
            postID: Data(repeating: id, count: 32),
            geohash: scope,
            content: content,
            authorSigningKey: Data(repeating: 1, count: 32),
            authorNickname: "alice",
            createdAt: createdAt,
            expiresAt: createdAt + 60_000,
            flags: 0,
            signature: Data(repeating: 2, count: 64)
        )
    }

    @Test func previewUsesNewestRelevantUnseenNotice() {
        let meshOld = post(1, scope: "", createdAt: 10, content: "mesh old")
        let geoNew = post(2, scope: "u4pr", createdAt: 30, content: "geo new")
        let geoUnseen = post(3, scope: "u4pr", createdAt: 20, content: "unseen geo")
        let unrelated = post(4, scope: "u4ps", createdAt: 40, content: "other area")
        let unseen = [geoUnseen.postID.hexEncodedString(): "u4pr"]

        #expect(PinnedNoticesBarState.previewPost([meshOld, geoNew, geoUnseen, unrelated], unseenScopes: unseen, geoScope: "u4pr") == geoUnseen)
    }

    @Test func previewFallsBackToNewestNoticeAndCountsOnlyVisibleScopes() {
        let mesh = post(1, scope: "", createdAt: 10, content: "mesh")
        let geo = post(2, scope: "u4pr", createdAt: 30, content: "geo")
        let unrelated = post(3, scope: "u4ps", createdAt: 40, content: "other")

        #expect(PinnedNoticesBarState.previewPost([mesh, geo, unrelated], unseenScopes: [:], geoScope: "u4pr") == geo)
        #expect(PinnedNoticesBarState.unseenCount(["a": "", "b": "u4pr", "c": "u4ps"], geoScope: "u4pr") == 2)
        #expect(PinnedNoticesBarState.relevantPosts([mesh, geo, unrelated], geoScope: "u4pr").count == 2)
    }
}
