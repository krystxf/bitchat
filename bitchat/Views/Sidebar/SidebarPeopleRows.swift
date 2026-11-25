//
// SidebarPeopleRows.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// The rows of one kind of person in the sidebar. Each row is tagged with
/// the conversation it opens, so selecting it in the sidebar list opens the
/// chat. Favorite, fingerprint and block live in the swipe actions and the
/// context menu.
///
/// Rows stay where they are while the sidebar shows them: see
/// `PeopleListOrderMemory`.
struct SidebarMeshPeerRows: View {
    let peers: [MeshPeerRow]
    let onOpen: (PeerID) -> Void

    @State private var orderMemory = PeopleListOrderMemory()

    var body: some View {
        let peerByID = Dictionary(peers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = orderMemory.order(peers.map(\.id)).compactMap { peerByID[$0] }
        ForEach(ordered) { peer in
            SidebarMeshPeerRow(peer: peer, onOpen: onOpen)
                .tag(SidebarItem.conversation(peer.peerID))
        }
    }
}

/// Someone on the Bluetooth mesh, or a mutual favorite reachable over Nostr.
private struct SidebarMeshPeerRow: View {
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel

    let peer: MeshPeerRow
    let onOpen: (PeerID) -> Void

    private enum Strings {
        static let blockedTooltip = String(localized: "geohash_people.tooltip.blocked", comment: "Tooltip shown next to a blocked peer indicator")
        static let favorite = String(localized: "mesh_peers.state.favorite", comment: "State label for a favorited peer")
        static let unread = String(localized: "mesh_peers.state.unread", comment: "State label for a peer with unread private messages")
        static let blocked = String(localized: "mesh_peers.state.blocked", comment: "State label for a blocked peer")
        static let vouched = String(localized: "mesh_peers.state.vouched", comment: "State label for a peer vouched for by someone the user verified")
        static let vouchedTooltip = String(localized: "mesh_peers.tooltip.vouched", comment: "Tooltip for the vouched (unfilled seal) badge next to a peer")
        static let addFavorite = String(localized: "content.accessibility.add_favorite", comment: "Accessibility label to add a favorite")
        static let removeFavorite = String(localized: "content.accessibility.remove_favorite", comment: "Accessibility label to remove a favorite")
        static let showFingerprint = String(localized: "mesh_peers.action.fingerprint", comment: "Context menu action that shows a peer's fingerprint/verification screen")
        static let openDMHint = String(localized: "mesh_peers.accessibility.open_dm_hint", comment: "Accessibility hint on a peer row explaining activation opens a private chat")
        static let directMessage = String(localized: "content.actions.direct_message", comment: "Action that opens a private chat with the person")
        static let block = String(localized: "geohash_people.action.block", comment: "Context menu action to block a person")
        static let unblock = String(localized: "geohash_people.action.unblock", comment: "Context menu action to unblock a person")
    }

    var body: some View {
        rowContent
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                favoriteButton
                    .tint(.yellow)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Tint, not the destructive role: a destructive swipe action
                // animates the row away, and a blocked peer stays listed.
                blockButton
                    .tint(peer.isBlocked ? .gray : .red)
                fingerprintButton
                    .tint(.blue)
            }
            .contextMenu {
                Button {
                    onOpen(peer.peerID)
                } label: {
                    Label(Strings.directMessage, systemImage: "bubble.left")
                }
                favoriteButton
                fingerprintButton
                if peer.isBlocked {
                    Button(action: toggleBlock) {
                        Label(Strings.unblock, systemImage: "checkmark.circle")
                    }
                } else {
                    Button(role: .destructive, action: toggleBlock) {
                        Label(Strings.block, systemImage: "nosign")
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint(Strings.openDMHint)
            .accessibilityActions {
                Button(peer.isFavorite ? Strings.removeFavorite : Strings.addFavorite, action: toggleFavorite)
                Button(Strings.showFingerprint, action: showFingerprint)
                Button(peer.isBlocked ? Strings.unblock : Strings.block, action: toggleBlock)
            }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Label(
                peer.isFavorite ? Strings.removeFavorite : Strings.addFavorite,
                systemImage: peer.isFavorite ? "star.slash" : "star"
            )
        }
    }

    private var fingerprintButton: some View {
        Button(action: showFingerprint) {
            Label(Strings.showFingerprint, systemImage: "checkmark.shield")
        }
    }

    private var blockButton: some View {
        Button(action: toggleBlock) {
            Label(
                peer.isBlocked ? Strings.unblock : Strings.block,
                systemImage: peer.isBlocked ? "checkmark.circle" : "nosign"
            )
        }
    }

    private func toggleFavorite() {
        peerListModel.toggleFavorite(peerID: peer.peerID)
    }

    private func showFingerprint() {
        appChromeModel.showFingerprint(for: peer.peerID)
    }

    private func toggleBlock() {
        if peer.isBlocked {
            conversationUIModel.unblock(peerID: peer.peerID, displayName: peer.displayName)
        } else {
            conversationUIModel.block(peerID: peer.peerID, displayName: peer.displayName)
        }
    }

    private var rowContent: some View {
        let presence = peer.presence
        return PeopleRow(subtitle: presence.label) {
            SidebarPersonAvatar(name: peer.displayName, peerID: peer.peerID, presence: presence)
        } title: {
            PeopleRowName(name: peer.displayName)
        } accessories: {
            if peer.isBlocked {
                Image(systemName: "nosign")
                    .foregroundColor(.red)
                    .help(Strings.blockedTooltip)
            }
            if let icon = encryptionIcon {
                Image(systemName: icon)
                    // Optical centering: lock glyph ink is bottom-heavy, so
                    // geometric centering reads low.
                    .offset(y: icon.hasPrefix("lock") ? -0.5 : 0)
                    .foregroundStyle(.secondary)
            }
            // Vouched (transitively verified): the unfilled seal, distinct
            // from verified's filled one. Never shown with a verified badge.
            if peer.showsVouchedBadge {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .help(Strings.vouchedTooltip)
            }
            if peer.hasUnread {
                PeopleUnreadIndicator()
            }
            if peer.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
        }
    }

    /// Connected peers show their live session state. Offline peers prefer
    /// the verified seal from persisted fingerprints, then whatever the last
    /// session left (likely a lock).
    private var encryptionIcon: String? {
        if !peer.isConnected && peer.showsVerifiedBadgeWhenOffline {
            return "checkmark.seal.fill"
        }
        return peer.encryptionStatus.icon
    }

    /// One spoken sentence per row: name, how they're reachable, and any
    /// state badges. The visual row is icon soup for VoiceOver otherwise.
    private var accessibilityDescription: String {
        var parts: [String] = [peer.displayName, peer.presence.label]
        if peer.showsVouchedBadge { parts.append(Strings.vouched) }
        if peer.isFavorite { parts.append(Strings.favorite) }
        if peer.hasUnread { parts.append(Strings.unread) }
        if peer.isBlocked { parts.append(Strings.blocked) }
        return parts.joined(separator: ", ")
    }
}

/// People seen in the current location channel: those physically here
/// first, then those who teleported in. A row opens a geohash DM.
struct SidebarGeohashPeopleRows: View {
    let people: [GeohashPersonRow]
    let onOpen: (PeerID) -> Void

    @State private var orderMemory = PeopleListOrderMemory()

    var body: some View {
        let personByID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let displayed = orderMemory.order(people.map(\.id)).compactMap { personByID[$0] }
        let rows = displayed.filter { !$0.isTeleported } + displayed.filter(\.isTeleported)
        // The list builds only the visible rows, so a busy room with
        // hundreds of people stays cheap.
        ForEach(rows) { person in
            SidebarGeohashPersonRow(person: person, onOpen: onOpen)
                .tag(SidebarItem.conversation(PeerID(nostr_: person.id)))
        }
    }
}

private struct SidebarGeohashPersonRow: View {
    @EnvironmentObject private var peerListModel: PeerListModel

    let person: GeohashPersonRow
    let onOpen: (PeerID) -> Void

    private enum Strings {
        static let blockedTooltip = String(localized: "geohash_people.tooltip.blocked", comment: "Tooltip shown next to users blocked in geohash channels")
        static let unblock = String(localized: "geohash_people.action.unblock", comment: "Context menu action to unblock a person")
        static let block = String(localized: "geohash_people.action.block", comment: "Context menu action to block a person")
        static let blockedState = String(localized: "mesh_peers.state.blocked", comment: "State label for a blocked peer")
        static let openDMHint = String(localized: "mesh_peers.accessibility.open_dm_hint", comment: "Accessibility hint on a peer row explaining activation opens a private chat")
        static let directMessage = String(localized: "content.actions.direct_message", comment: "Action that opens a private chat with the person")
    }

    var body: some View {
        PeopleRow(subtitle: person.presence.label) {
            // Seeded by their Nostr key, as beside their channel messages.
            SidebarPersonAvatar(name: person.displayName, peerID: PeerID(nostr_: person.id), presence: person.presence)
        } title: {
            PeopleRowName(name: person.displayName)
        } accessories: {
            if person.isBlocked {
                Image(systemName: "nosign")
                    .foregroundColor(.red)
                    .help(Strings.blockedTooltip)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Tint, not the destructive role: a destructive swipe action
            // animates the row away, and a blocked person stays listed.
            blockButton
                .tint(person.isBlocked ? .gray : .red)
        }
        .contextMenu {
            Button {
                onOpen(PeerID(nostr_: person.id))
            } label: {
                Label(Strings.directMessage, systemImage: "bubble.left")
            }
            blockButton
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(Strings.openDMHint)
        .accessibilityActions {
            Button(person.isBlocked ? Strings.unblock : Strings.block, action: toggleBlock)
        }
    }

    private var blockButton: some View {
        Button(action: toggleBlock) {
            Label(
                person.isBlocked ? Strings.unblock : Strings.block,
                systemImage: person.isBlocked ? "checkmark.circle" : "nosign"
            )
        }
    }

    private func toggleBlock() {
        if person.isBlocked {
            peerListModel.unblockGeohashUser(pubkeyHexLowercased: person.id, displayName: person.displayName)
        } else {
            peerListModel.blockGeohashUser(pubkeyHexLowercased: person.id, displayName: person.displayName)
        }
    }

    /// One spoken sentence per row: name, presence type, and block state.
    private var accessibilityDescription: String {
        var parts: [String] = [person.displayName, person.presence.label]
        if person.isBlocked { parts.append(Strings.blockedState) }
        return parts.joined(separator: ", ")
    }
}

/// Direct conversations with people no roster above lists: the offline
/// passerby, the geohash DM from a channel since left, and message
/// requests. Without these rows such a thread had no way back in.
struct SidebarChatRows: View {
    let chats: [RecentChatRow]
    let onOpen: (PeerID) -> Void

    var body: some View {
        ForEach(chats) { chat in
            SidebarChatRow(chat: chat, onOpen: onOpen)
                .tag(SidebarItem.conversation(chat.peerID))
        }
    }
}

private struct SidebarChatRow: View {
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel

    let chat: RecentChatRow
    let onOpen: (PeerID) -> Void

    private enum Strings {
        static let unread = String(localized: "mesh_peers.state.unread", comment: "State label for a peer with unread private messages")
        static let favorite = String(localized: "mesh_peers.state.favorite", comment: "State label for a favorited peer")
        static let openChatHint = String(localized: "chats.accessibility.open_hint", defaultValue: "Opens this conversation", comment: "Accessibility hint on a recent chat row explaining activation opens the direct conversation")
        static let directMessage = String(localized: "content.actions.direct_message", comment: "Action that opens a private chat with the person")
        static let addFavorite = String(localized: "content.accessibility.add_favorite", comment: "Accessibility label to add a favorite")
        static let removeFavorite = String(localized: "content.accessibility.remove_favorite", comment: "Accessibility label to remove a favorite")
        static let showFingerprint = String(localized: "mesh_peers.action.fingerprint", comment: "Context menu action that shows a peer's fingerprint/verification screen")
        static let block = String(localized: "geohash_people.action.block", comment: "Context menu action to block a person")
    }

    /// Relative "5 min ago" stamps; the formatter is locale-aware.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// A geohash DM has no Noise identity to favorite or verify.
    private var hasMeshIdentity: Bool { !chat.peerID.isGeoDM }

    var body: some View {
        // No presence badge: nobody listed here is in a roster, and the
        // detail line is the last activity, as in Messages.
        PeopleRow(subtitle: lastActivityText) {
            SidebarPersonAvatar(name: chat.displayName, peerID: chat.peerID)
        } title: {
            PeopleRowName(name: chat.displayName)
        } accessories: {
            if chat.hasUnread {
                PeopleUnreadIndicator()
            }
            if chat.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if hasMeshIdentity {
                favoriteButton
                    .tint(.yellow)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Tint, not the destructive role: the row leaves on its own
            // once the block lands.
            blockButton
                .tint(.red)
            if hasMeshIdentity {
                fingerprintButton
                    .tint(.blue)
            }
        }
        .contextMenu {
            Button {
                onOpen(chat.peerID)
            } label: {
                Label(Strings.directMessage, systemImage: "bubble.left")
            }
            if hasMeshIdentity {
                favoriteButton
                fingerprintButton
            }
            Button(role: .destructive, action: block) {
                Label(Strings.block, systemImage: "nosign")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(Strings.openChatHint)
        .accessibilityActions {
            if hasMeshIdentity {
                Button(chat.isFavorite ? Strings.removeFavorite : Strings.addFavorite, action: toggleFavorite)
                Button(Strings.showFingerprint, action: showFingerprint)
            }
            Button(Strings.block, action: block)
        }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Label(
                chat.isFavorite ? Strings.removeFavorite : Strings.addFavorite,
                systemImage: chat.isFavorite ? "star.slash" : "star"
            )
        }
    }

    private var fingerprintButton: some View {
        Button(action: showFingerprint) {
            Label(Strings.showFingerprint, systemImage: "checkmark.shield")
        }
    }

    private var blockButton: some View {
        Button(action: block) {
            Label(Strings.block, systemImage: "nosign")
        }
    }

    private func toggleFavorite() {
        peerListModel.toggleFavorite(peerID: chat.peerID)
    }

    private func showFingerprint() {
        appChromeModel.showFingerprint(for: chat.peerID)
    }

    private func block() {
        conversationUIModel.block(peerID: chat.peerID, displayName: chat.displayName)
    }

    private var lastActivityText: String {
        Self.relativeFormatter.localizedString(for: chat.lastActivity, relativeTo: Date())
    }

    private var accessibilityDescription: String {
        var parts: [String] = [chat.displayName, lastActivityText]
        if chat.isFavorite { parts.append(Strings.favorite) }
        if chat.hasUnread { parts.append(Strings.unread) }
        return parts.joined(separator: ", ")
    }
}

/// People visible across the mesh bridge: same place, beyond radio range.
/// Display-only: bridged identities are per-cell rendezvous keys with no DM
/// route yet, so the rows have no tag and no actions.
struct SidebarBridgedPeopleRows: View {
    let people: [BridgeService.BridgedParticipant]

    private enum Strings {
        static let rowHint = String(localized: "bridge_people.accessibility.row_hint", defaultValue: "In your area, connected through the bridge", comment: "Accessibility hint for a person listed in the bridge section of the people sheet")
    }

    var body: some View {
        ForEach(people) { person in
            PeopleRow(subtitle: PersonPresence.bridged.label) {
                // The seed of their bridged messages' sender ID.
                SidebarPersonAvatar(name: person.displayName, peerID: PeerID(bridge: person.pubkey), presence: .bridged)
            } title: {
                PeopleRowName(name: person.displayName)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(person.displayName)
            .accessibilityHint(Strings.rowHint)
        }
    }
}

/// A private group this device belongs to. Selecting it opens the group
/// chat.
struct SidebarGroupRow: View {
    let group: GroupChatRow

    private enum Strings {
        static let creator = String(localized: "groups.state.creator", comment: "State label for a group the user created")
        static let unread = String(localized: "mesh_peers.state.unread", comment: "State label for a peer with unread private messages")
        static let openGroupHint = String(localized: "groups.accessibility.open_group_hint", comment: "Accessibility hint on a group row explaining activation opens the group chat")
        static let memberCountFormat = String(localized: "groups.member_count %@", comment: "Member count shown next to a group name; placeholder is the count")
    }

    var body: some View {
        PeopleRow(subtitle: memberCount) {
            SidebarAvatar { size in
                GroupAvatar(groupID: group.peerID, size: size)
            }
        } title: {
            hashtagText
                .lineLimit(1)
                .truncationMode(.tail)
        } accessories: {
            if group.isCreator {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                    .help(Strings.creator)
            }
            if group.hasUnread {
                PeopleUnreadIndicator()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(Strings.openGroupHint)
    }

    private var memberCount: String {
        String(format: Strings.memberCountFormat, locale: .current, "\(group.memberCount)")
    }

    /// "#name", not localized: there is nothing to translate, and a
    /// letterless "#%@" catalog key breaks string catalog symbol generation
    /// (SwiftPM's default build system). The name is isolated, so the "#"
    /// stays on the same side of right-to-left names, and the text is tagged
    /// with the app language, as text from a localization table is.
    private var hashtagText: Text {
        var hashtag = AttributedString("#\u{2068}\(group.name)\u{2069}")
        hashtag.languageIdentifier = Bundle.main.preferredLocalizations.first ?? "en"
        return Text(hashtag)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [group.name, memberCount]
        if group.isCreator { parts.append(Strings.creator) }
        if group.hasUnread { parts.append(Strings.unread) }
        return parts.joined(separator: ", ")
    }
}
