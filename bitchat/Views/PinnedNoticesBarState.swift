import Foundation

/// Pure selection and badge logic for the sticky notices bar.
enum PinnedNoticesBarState {
    static func relevantPosts(_ posts: [BoardPostPacket], geoScope: String?) -> [BoardPostPacket] {
        posts.filter { $0.geohash.isEmpty || $0.geohash == geoScope }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func previewPost(_ posts: [BoardPostPacket], unseenScopes: [String: String], geoScope: String?) -> BoardPostPacket? {
        let relevant = relevantPosts(posts, geoScope: geoScope)
        let unseenIDs = Set(unseenScopes.filter { $0.value.isEmpty || $0.value == geoScope }.map(\.key))
        return relevant.first(where: { unseenIDs.contains($0.postID.hexEncodedString()) }) ?? relevant.first
    }

    static func unseenCount(_ unseenScopes: [String: String], geoScope: String?) -> Int {
        unseenScopes.values.reduce(0) { count, scope in
            count + ((scope.isEmpty || scope == geoScope) ? 1 : 0)
        }
    }
}
