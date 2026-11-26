//
// SidebarSampleData.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

#if DEBUG
import BitFoundation
import Foundation

/// Made-up sidebar rows for screenshots and design review: contacts,
/// unknown people, groups and bookmarked channels. Debug builds only.
///
/// Launch with `-SidebarSampleData YES` to show them in place of the live
/// rosters. The rows are display-only: the live models never see them.
enum SidebarSampleData {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "SidebarSampleData")
    }

    /// `-SidebarStartsOnList YES`: an iPhone opens on the list, not the chat.
    static var startsOnList: Bool {
        UserDefaults.standard.bool(forKey: "SidebarStartsOnList")
    }

    static let meshRows: [MeshPeerRow] = [
        peer("a1", "Alice Novak", connected: true, favorite: true, unread: true, encryption: .noiseVerified, verified: true),
        peer("b2", "Ben Carter", reachable: true, encryption: .noiseSecured, accepted: true),
        peer("c3", "Chloé Martin", favorite: true, mutualFavorite: true, verifiedOffline: true, verified: true),
        peer("d4", "dmitri#a1b2", vouched: true, accepted: true),
        peer("e5", "Eve", connected: true),
        peer("f6", "frank_on_the_bus", reachable: true, unread: true, encryption: .noiseHandshaking),
        peer("g7", "Spammy McSpamface", connected: true, blocked: true)
    ]

    static let geohashPeople: [GeohashPersonRow] = [
        GeohashPersonRow(id: hex("71"), displayName: "Gina#9f3c", isMe: false, isTeleported: false, isBlocked: false, hasAcceptedConversation: true),
        GeohashPersonRow(id: hex("72"), displayName: "Hugo", isMe: false, isTeleported: false, isBlocked: false, hasAcceptedConversation: false),
        GeohashPersonRow(id: hex("73"), displayName: "Ines from far away", isMe: false, isTeleported: true, isBlocked: false, hasAcceptedConversation: false)
    ]

    static let chats: [RecentChatRow] = [
        RecentChatRow(peerID: PeerID(str: hex("81").prefix(16)), displayName: "Jonas", hasUnread: false, lastActivity: Date().addingTimeInterval(-2 * 3600), isFavorite: true, isVerified: false, hasAcceptedConversation: true),
        RecentChatRow(peerID: PeerID(str: hex("82").prefix(16)), displayName: "Kim (message request)", hasUnread: true, lastActivity: Date().addingTimeInterval(-6 * 60), isFavorite: false, isVerified: false, hasAcceptedConversation: false)
    ]

    static let groupRows: [GroupChatRow] = [
        GroupChatRow(peerID: PeerID(groupID: Data(repeating: 0x1A, count: 16)), name: "Weekend Hike", memberCount: 5, isCreator: true, hasUnread: true),
        GroupChatRow(peerID: PeerID(groupID: Data(repeating: 0x2B, count: 16)), name: "Book Club", memberCount: 12, isCreator: false, hasUnread: false)
    ]

    static let bookmarks = ["u2fkbn", "9q8yy"]
    static let bookmarkNames = ["u2fkbn": "Prague", "9q8yy": "San Francisco"]

    static func participantCount(for geohash: String) -> Int {
        geohash == "u2fkbn" ? 14 : 3
    }

    static let meshPeopleCount = 4

    static let blockedAccounts: [BlockedAccount] = [
        BlockedAccount(kind: .mesh(fingerprint: hex("9a")), name: "Spammy McSpamface"),
        BlockedAccount(kind: .nostr(pubkeyHex: hex("9b")), name: "loud_stranger")
    ]

    private static func hex(_ seed: String) -> String {
        String(repeating: seed, count: 32)
    }

    private static func peer(
        _ seed: String,
        _ name: String,
        connected: Bool = false,
        reachable: Bool = false,
        favorite: Bool = false,
        mutualFavorite: Bool = false,
        unread: Bool = false,
        blocked: Bool = false,
        encryption: EncryptionStatus = .noHandshake,
        verifiedOffline: Bool = false,
        vouched: Bool = false,
        verified: Bool = false,
        accepted: Bool = false
    ) -> MeshPeerRow {
        MeshPeerRow(
            peerID: PeerID(str: String(repeating: seed, count: 8)),
            displayName: name,
            isMe: false,
            hasUnread: unread,
            isBlocked: blocked,
            isFavorite: favorite,
            isConnected: connected,
            isReachable: reachable || connected,
            isMutualFavorite: mutualFavorite,
            encryptionStatus: encryption,
            showsVerifiedBadgeWhenOffline: verifiedOffline,
            showsVouchedBadge: vouched,
            isVerified: verified,
            hasAcceptedConversation: accepted
        )
    }
}
#endif
