//
// SidebarPeople.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

/// The facts that decide whether a person is a contact.
///
/// The sidebar lists contacts openly and keeps everyone else under a
/// collapsed "unknown" group, so strangers and spam stay out of sight until
/// the user asks for them. A contact is someone the user chose: a favorite,
/// a verified identity, or a direct conversation the user opened or wrote
/// in. Blocking someone always moves them out of the contacts.
struct ContactStanding: Equatable {
    var isMe = false
    var isBlocked = false
    var isFavorite = false
    var isVerified = false
    var hasAcceptedConversation = false

    var isContact: Bool {
        guard !isMe, !isBlocked else { return false }
        return isFavorite || isVerified || hasAcceptedConversation
    }
}

extension MeshPeerRow {
    var standing: ContactStanding {
        ContactStanding(
            isMe: isMe,
            isBlocked: isBlocked,
            isFavorite: isFavorite,
            isVerified: isVerified,
            hasAcceptedConversation: hasAcceptedConversation
        )
    }
}

extension GeohashPersonRow {
    var standing: ContactStanding {
        ContactStanding(
            isMe: isMe,
            isBlocked: isBlocked,
            hasAcceptedConversation: hasAcceptedConversation
        )
    }
}

extension RecentChatRow {
    /// Blocked people get no chat row, so blocking needs no check here.
    var standing: ContactStanding {
        ContactStanding(
            isFavorite: isFavorite,
            isVerified: isVerified,
            hasAcceptedConversation: hasAcceptedConversation
        )
    }
}

/// One side of the sidebar's people: the contacts or the unknown people.
struct SidebarRoster: Equatable {
    var meshPeers: [MeshPeerRow] = []
    var geohashPeople: [GeohashPersonRow] = []
    var chats: [RecentChatRow] = []
    /// People across the mesh bridge. They have no direct-message route, so
    /// they are never contacts.
    var bridgedPeople: [BridgeService.BridgedParticipant] = []

    var count: Int {
        meshPeers.count + geohashPeople.count + chats.count + bridgedPeople.count
    }

    /// Rows with unread direct messages. Geohash and bridge rows carry no
    /// unread state: a geohash DM shows as a chat row.
    var unreadCount: Int {
        meshPeers.filter(\.hasUnread).count + chats.filter(\.hasUnread).count
    }

    var isEmpty: Bool { count == 0 }
}

/// The sidebar's people, split into contacts and unknown people.
struct SidebarPeople: Equatable {
    private(set) var contacts = SidebarRoster()
    private(set) var unknown = SidebarRoster()

    /// Keeps the order of each input. Your own rows are left out: the
    /// sidebar lists other people.
    init(
        meshPeers: [MeshPeerRow],
        geohashPeople: [GeohashPersonRow],
        chats: [RecentChatRow],
        bridgedPeople: [BridgeService.BridgedParticipant] = []
    ) {
        for peer in meshPeers where !peer.isMe {
            if peer.standing.isContact {
                contacts.meshPeers.append(peer)
            } else {
                unknown.meshPeers.append(peer)
            }
        }
        for person in geohashPeople where !person.isMe {
            if person.standing.isContact {
                contacts.geohashPeople.append(person)
            } else {
                unknown.geohashPeople.append(person)
            }
        }
        for chat in chats {
            if chat.standing.isContact {
                contacts.chats.append(chat)
            } else {
                unknown.chats.append(chat)
            }
        }
        unknown.bridgedPeople = bridgedPeople
    }
}
