import SwiftUI
import BitFoundation

/// The "#mesh" section of the people sheet: everyone on the Bluetooth mesh,
/// plus mutual favorites reachable over Nostr. Tapping a row opens the
/// private chat. Favorite, fingerprint and block live in the swipe actions
/// and the context menu.
struct MeshPeerList: View {
    @EnvironmentObject private var peerListModel: PeerListModel
    @ThemedPalette private var palette
    let onTapPeer: (PeerID) -> Void
    let onToggleFavorite: (PeerID) -> Void
    let onShowFingerprint: (PeerID) -> Void
    /// Optional so existing call sites (and previews/tests) keep compiling;
    /// when absent the block/unblock actions are hidden.
    var onToggleBlock: ((MeshPeerRow) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    @State private var orderMemory = PeopleListOrderMemory()

    private enum Strings {
        static let blockedTooltip = String(localized: "geohash_people.tooltip.blocked", comment: "Tooltip shown next to a blocked peer indicator")
        static let connected = String(localized: "content.accessibility.connected_mesh", comment: "Accessibility label for mesh-connected peer indicator")
        static let reachable = String(localized: "content.accessibility.reachable_mesh", comment: "Accessibility label for mesh-reachable peer indicator")
        static let nostr = String(localized: "content.accessibility.available_nostr", comment: "Accessibility label for Nostr-available peer indicator")
        static let offline = String(localized: "mesh_peers.state.offline", comment: "State label for a peer that is not currently reachable")
        static let you = String(localized: "geohash_people.state.you", comment: "State label marking your own row in the people list")
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
        let rowByID = Dictionary(peerListModel.meshRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let peers: [MeshPeerRow] = orderMemory.order(peerListModel.meshRows.map(\.id))
            .compactMap { rowByID[$0] }

        Section {
            if peers.isEmpty {
                PeopleEmptyRow()
            } else {
                ForEach(peers) { peer in
                    if peer.isMe {
                        rowContent(for: peer)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(accessibilityDescription(for: peer))
                    } else {
                        peerRow(for: peer)
                    }
                }
            }
        } header: {
            Text(verbatim: "#mesh")
        }
    }

    private func peerRow(for peer: MeshPeerRow) -> some View {
        Button {
            onTapPeer(peer.peerID)
        } label: {
            rowContent(for: peer)
        }
        .peopleRowButtonStyle()
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            favoriteButton(for: peer)
                .tint(.yellow)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onToggleBlock {
                // Tint, not the destructive role: a destructive swipe action
                // animates the row away, and a blocked peer stays listed.
                Button {
                    onToggleBlock(peer)
                } label: {
                    Label(
                        peer.isBlocked ? Strings.unblock : Strings.block,
                        systemImage: peer.isBlocked ? "checkmark.circle" : "nosign"
                    )
                }
                .tint(peer.isBlocked ? .gray : .red)
            }
            fingerprintButton(for: peer)
                .tint(.blue)
        }
        .contextMenu {
            Button {
                onTapPeer(peer.peerID)
            } label: {
                Label(Strings.directMessage, systemImage: "bubble.left")
            }
            favoriteButton(for: peer)
            fingerprintButton(for: peer)
            if let onToggleBlock {
                if peer.isBlocked {
                    Button {
                        onToggleBlock(peer)
                    } label: {
                        Label(Strings.unblock, systemImage: "checkmark.circle")
                    }
                } else {
                    Button(role: .destructive) {
                        onToggleBlock(peer)
                    } label: {
                        Label(Strings.block, systemImage: "nosign")
                    }
                }
            }
        }
        .accessibilityLabel(accessibilityDescription(for: peer))
        .accessibilityHint(Strings.openDMHint)
        .accessibilityActions {
            Button(peer.isFavorite ? Strings.removeFavorite : Strings.addFavorite) {
                onToggleFavorite(peer.peerID)
            }
            Button(Strings.showFingerprint) {
                onShowFingerprint(peer.peerID)
            }
            if let onToggleBlock {
                Button(peer.isBlocked ? Strings.unblock : Strings.block) {
                    onToggleBlock(peer)
                }
            }
        }
    }

    private func favoriteButton(for peer: MeshPeerRow) -> some View {
        Button {
            onToggleFavorite(peer.peerID)
        } label: {
            Label(
                peer.isFavorite ? Strings.removeFavorite : Strings.addFavorite,
                systemImage: peer.isFavorite ? "star.slash" : "star"
            )
        }
    }

    private func fingerprintButton(for peer: MeshPeerRow) -> some View {
        Button {
            onShowFingerprint(peer.peerID)
        } label: {
            Label(Strings.showFingerprint, systemImage: "checkmark.shield")
        }
    }

    private func rowContent(for peer: MeshPeerRow) -> some View {
        let reachability = reachability(for: peer)
        return PeopleRow(
            systemImage: reachability.icon,
            iconColor: reachability.color,
            subtitle: reachability.label
        ) {
            PeopleRowName(name: peer.displayName)
        } accessories: {
            if peer.isBlocked {
                Image(systemName: "nosign")
                    .foregroundColor(.red)
                    .help(Strings.blockedTooltip)
            }
            if !peer.isMe {
                if let icon = encryptionIcon(for: peer) {
                    Image(systemName: icon)
                        // Optical centering: lock glyph ink is bottom-heavy,
                        // so geometric centering reads low.
                        .offset(y: icon.hasPrefix("lock") ? -0.5 : 0)
                        .foregroundColor(palette.secondary)
                }
                // Vouched (transitively verified): the unfilled seal,
                // deliberately distinct from verified's filled one. Never
                // shown alongside a verified badge.
                if peer.showsVouchedBadge {
                    Image(systemName: "checkmark.seal")
                        .foregroundColor(palette.secondary)
                        .help(Strings.vouchedTooltip)
                }
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

    /// The leading glyph encodes HOW the peer is reachable (radio, relayed,
    /// Nostr), so mesh rows keep it. The tint is the color the peer's name
    /// has in the chat, which ties the row to their messages.
    private func reachability(for peer: MeshPeerRow) -> (icon: String, color: Color, label: String) {
        if peer.isMe {
            return ("person.fill", .orange, Strings.you)
        }
        let assigned = peerListModel.colorForMeshPeer(id: peer.peerID, isDark: colorScheme == .dark)
        if peer.isConnected {
            return ("antenna.radiowaves.left.and.right", assigned, Strings.connected)
        }
        if peer.isReachable {
            return ("point.3.filled.connected.trianglepath.dotted", assigned, Strings.reachable)
        }
        if peer.isMutualFavorite {
            return ("globe", .purple, Strings.nostr)
        }
        // Offline: the slashed variant of the connected glyph.
        return ("antenna.radiowaves.left.and.right.slash", palette.secondary, Strings.offline)
    }

    /// Connected peers show their live session state. Offline peers prefer
    /// the verified seal from persisted fingerprints, then whatever the
    /// last session left (likely a lock).
    private func encryptionIcon(for peer: MeshPeerRow) -> String? {
        if !peer.isConnected && peer.showsVerifiedBadgeWhenOffline {
            return "checkmark.seal.fill"
        }
        return peer.encryptionStatus.icon
    }

    /// One spoken sentence per row: name, how they're reachable, and any
    /// state badges — the visual row is icon soup for VoiceOver otherwise.
    private func accessibilityDescription(for peer: MeshPeerRow) -> String {
        var parts: [String] = [peer.displayName]
        if peer.isMe {
            parts.append(Strings.you)
        } else {
            if peer.isConnected {
                parts.append(Strings.connected)
            } else if peer.isReachable {
                parts.append(Strings.reachable)
            } else if peer.isMutualFavorite {
                parts.append(Strings.nostr)
            } else {
                parts.append(Strings.offline)
            }
        }
        if peer.showsVouchedBadge { parts.append(Strings.vouched) }
        if peer.isFavorite { parts.append(Strings.favorite) }
        if peer.hasUnread { parts.append(Strings.unread) }
        if peer.isBlocked { parts.append(Strings.blocked) }
        return parts.joined(separator: ", ")
    }
}
