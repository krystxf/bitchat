import BitFoundation
import Combine
import SwiftUI

struct MeshPeerRow: Identifiable, Equatable {
    let peerID: PeerID
    let displayName: String
    let isMe: Bool
    let hasUnread: Bool
    let isBlocked: Bool
    let isFavorite: Bool
    let isConnected: Bool
    let isReachable: Bool
    let isMutualFavorite: Bool
    let encryptionStatus: EncryptionStatus
    let showsVerifiedBadgeWhenOffline: Bool
    /// Vouched-for by someone I verified, without an explicit verification of
    /// mine — rendered as the unfilled seal (verified gets the filled one).
    let showsVouchedBadge: Bool
    /// I verified this person's fingerprint.
    let isVerified: Bool
    /// I wrote in a direct conversation with this person.
    let hasAcceptedConversation: Bool
    /// I saved a name (petname) for this person.
    var hasPetname = false

    var id: String { peerID.id }
}

struct GeohashPersonRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isMe: Bool
    let isTeleported: Bool
    let isBlocked: Bool
    /// I wrote in a geohash DM with this person.
    let hasAcceptedConversation: Bool
}

struct GroupChatRow: Identifiable, Equatable {
    let peerID: PeerID
    let name: String
    let memberCount: Int
    let isCreator: Bool
    let hasUnread: Bool

    var id: String { peerID.id }
}

/// A direct conversation whose person is NOT in any roster above it. Without
/// this section, a DM from a passerby became unreachable the moment they went
/// offline: the roster filters to connected/reachable/mutual-favorite, the
/// header envelope only exists while unread, and /msg can't resolve offline
/// strangers — the thread was still in memory with no row anywhere in the UI.
struct RecentChatRow: Identifiable, Equatable {
    let peerID: PeerID
    let displayName: String
    let hasUnread: Bool
    let lastActivity: Date
    let isFavorite: Bool
    let isVerified: Bool
    /// I wrote in this conversation. A chat that only holds messages from
    /// the other side is a message request, even after I opened it.
    let hasAcceptedConversation: Bool
    /// I saved a name (petname) for this person.
    var hasPetname = false

    var id: String { peerID.id }
}

@MainActor
final class PeerListModel: ObservableObject {
    @Published private(set) var meshRows: [MeshPeerRow] = []
    @Published private(set) var geohashPeople: [GeohashPersonRow] = []
    @Published private(set) var groupRows: [GroupChatRow] = []
    @Published private(set) var recentChatRows: [RecentChatRow] = []
    @Published private(set) var reachableMeshPeerCount = 0
    @Published private(set) var connectedMeshPeerCount = 0
    @Published private(set) var visibleGeohashPeerCount = 0

    private let chatViewModel: ChatViewModel
    private let conversations: ConversationStore
    private let locationChannelsModel: LocationChannelsModel
    private let peerIdentityStore: PeerIdentityStore
    private let locationPresenceStore: LocationPresenceStore
    /// The mesh roster `refresh()` builds rows from. Not published: no view
    /// reads it, and publishing it would re-render on every mesh snapshot.
    private var allPeers: [BitchatPeer] = []
    /// Direct conversations I opened or wrote in, by routing peer ID. Their
    /// people count as contacts. Held in memory only, like the
    /// conversations themselves; an entry goes when its conversation does.
    private var acceptedConversationPeerIDs = Set<PeerID>()
    private var cancellables = Set<AnyCancellable>()
    private var refreshScheduled = false

    init(
        chatViewModel: ChatViewModel,
        conversations: ConversationStore,
        locationChannelsModel: LocationChannelsModel? = nil,
        peerIdentityStore: PeerIdentityStore? = nil,
        locationPresenceStore: LocationPresenceStore? = nil
    ) {
        self.chatViewModel = chatViewModel
        self.conversations = conversations
        self.locationChannelsModel = locationChannelsModel ?? LocationChannelsModel()
        self.peerIdentityStore = peerIdentityStore ?? chatViewModel.peerIdentityStore
        self.locationPresenceStore = locationPresenceStore ?? chatViewModel.locationPresenceStore
        self.allPeers = chatViewModel.allPeers

        bind()
        refresh()
    }

    func participantCount(for geohash: String) -> Int {
        chatViewModel.geohashParticipantCount(for: geohash)
    }

    func toggleFavorite(peerID: PeerID) {
        chatViewModel.toggleFavorite(peerID: peerID)
    }

    /// The full Nostr pubkey behind a geohash DM key, while the person is in
    /// the location channel's roster. A geohash row is tagged with the short
    /// DM key, and opening the DM needs the full key.
    func geohashPubkeyHex(forConversation peerID: PeerID) -> String? {
        guard peerID.isGeoDM else { return nil }
        return geohashPeople.first { PeerID(nostr_: $0.id) == peerID }?.id
    }

    func blockGeohashUser(pubkeyHexLowercased: String, displayName: String) {
        chatViewModel.blockGeohashUser(
            pubkeyHexLowercased: pubkeyHexLowercased,
            displayName: displayName
        )
    }

    func unblockGeohashUser(pubkeyHexLowercased: String, displayName: String) {
        chatViewModel.unblockGeohashUser(
            pubkeyHexLowercased: pubkeyHexLowercased,
            displayName: displayName
        )
    }

    private func bind() {
        // No equality guard: `BitchatPeer.==` compares only peer IDs, so a
        // rename or a connection, favorite or petname change looks unchanged,
        // and blocking someone republishes identical peers. The refresh is
        // coalesced, and rows are compared in full before they're written.
        chatViewModel.$allPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                guard let self else { return }
                self.allPeers = peers
                self.setNeedsRefresh()
            }
            .store(in: &cancellables)

        chatViewModel.$nickname
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        locationPresenceStore.$teleportedGeo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        conversations.$unreadConversations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        // Direct-conversation changes reorder or create recent-chat rows.
        // Filtered to `.direct` so public-timeline traffic (every mesh or
        // geohash message emits a change) doesn't rebuild the sidebar.
        conversations.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                self.noteAcceptance(from: change)
                guard case .direct = Self.changedConversationID(change) else { return }
                self.setNeedsRefresh()
            }
            .store(in: &cancellables)

        chatViewModel.groupStore.$groups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        peerIdentityStore.$encryptionStatuses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        peerIdentityStore.$verifiedFingerprints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: Notification.Name("peerStatusUpdated"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        chatViewModel.participantTracker.$visiblePeople
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        locationChannelsModel.$selectedChannel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        locationChannelsModel.$teleported
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)

        locationChannelsModel.$availableChannels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsRefresh()
            }
            .store(in: &cancellables)
    }

    /// Coalesces bursts of triggers into one rebuild per main-queue turn: a
    /// participant event republishes the roster and the teleport set, and a
    /// mesh snapshot touches peers, unread and encryption state at once.
    private func setNeedsRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshScheduled = false
                self.refresh()
            }
        }
    }

    private func refresh() {
        pruneAcceptedConversations()
        let acceptance = AcceptedConversations(
            peerIDs: acceptedConversationPeerIDs,
            fingerprints: Set(acceptedConversationPeerIDs.compactMap { chatViewModel.getFingerprint(for: $0) })
        )
        let myPeerID = chatViewModel.meshService.myPeerID
        let meshRows = allPeers.map { peer in
            let isMe = peer.peerID == myPeerID
            let fingerprint = isMe ? nil : chatViewModel.getFingerprint(for: peer.peerID)
            let isVerifiedFingerprint = fingerprint.map { peerIdentityStore.isVerified($0) } ?? false
            let verifiedBadge = !peer.isConnected && isVerifiedFingerprint
            // Vouched is subordinate to verified: never show both seals.
            let vouchedBadge = !isVerifiedFingerprint
                && (fingerprint.map { chatViewModel.isVouchedFingerprint($0) } ?? false)

            return MeshPeerRow(
                peerID: peer.peerID,
                displayName: isMe ? chatViewModel.nickname : peer.displayName,
                isMe: isMe,
                hasUnread: chatViewModel.hasUnreadMessages(for: peer.peerID),
                isBlocked: !isMe && chatViewModel.isPeerBlocked(peer.peerID),
                isFavorite: peer.favoriteStatus?.isFavorite ?? false,
                isConnected: peer.isConnected,
                isReachable: peer.isReachable,
                isMutualFavorite: peer.isMutualFavorite,
                encryptionStatus: chatViewModel.getEncryptionStatus(for: peer.peerID),
                showsVerifiedBadgeWhenOffline: verifiedBadge,
                showsVouchedBadge: vouchedBadge,
                isVerified: isVerifiedFingerprint,
                hasAcceptedConversation: !isMe && acceptance.contains(peer.peerID, fingerprint: fingerprint),
                hasPetname: !isMe && chatViewModel.localPetname(for: peer.peerID) != nil
            )
        }

        let meshCounts = meshRows.reduce(into: (reachable: 0, connected: 0)) { counts, row in
            guard !row.isMe else { return }
            if row.isConnected {
                counts.connected += 1
                counts.reachable += 1
            } else if row.isReachable {
                counts.reachable += 1
            }
        }

        let geohashPeople = buildGeohashPeople(acceptance: acceptance)
        let groupRows = buildGroupRows()
        let recentChatRows = buildRecentChatRows(
            meshRows: meshRows,
            geohashPeople: geohashPeople,
            acceptance: acceptance
        )

        // Assign only what changed: every @Published write re-renders every
        // view observing this model (root, header, sidebar).
        if self.meshRows != meshRows { self.meshRows = meshRows }
        if reachableMeshPeerCount != meshCounts.reachable { reachableMeshPeerCount = meshCounts.reachable }
        if connectedMeshPeerCount != meshCounts.connected { connectedMeshPeerCount = meshCounts.connected }
        if self.geohashPeople != geohashPeople { self.geohashPeople = geohashPeople }
        if visibleGeohashPeerCount != geohashPeople.count { visibleGeohashPeerCount = geohashPeople.count }
        if self.groupRows != groupRows { self.groupRows = groupRows }
        if self.recentChatRows != recentChatRows { self.recentChatRows = recentChatRows }
    }

    /// Direct conversations with people absent from the rosters above:
    /// the offline passerby DM, the geoDM from a channel since left. Rows
    /// mirrored under both an ephemeral and a stable peer ID collapse to
    /// one row per identity (newest activity wins), matching how the
    /// private-chat coordinators consolidate on open.
    private func buildRecentChatRows(
        meshRows: [MeshPeerRow],
        geohashPeople: [GeohashPersonRow],
        acceptance: AcceptedConversations
    ) -> [RecentChatRow] {
        // A conversation can be keyed by the stable Noise peer ID while the
        // roster lists the ephemeral one — compare fingerprints too.
        var visibleIdentities = Set<String>()
        for row in meshRows {
            visibleIdentities.insert(row.peerID.id)
            if let fingerprint = chatViewModel.getFingerprint(for: row.peerID) {
                visibleIdentities.insert(fingerprint)
            }
        }
        // Someone visible in the geohash section must not also get a chat
        // row: their GeoDM conversation is keyed by the nostr_ form of the
        // same pubkey the roster lists.
        for person in geohashPeople {
            visibleIdentities.insert(PeerID(nostr_: person.id).id)
        }

        struct Candidate {
            let peerID: PeerID
            let lastActivity: Date
        }
        var bestByIdentity: [String: Candidate] = [:]

        for (id, conversation) in conversations.conversationsByID {
            guard case .direct(let handle) = id else { continue }
            let peerID = handle.routingPeerID
            // Groups have their own section; blocked people get no row.
            guard !peerID.isGroup else { continue }
            guard let lastMessage = conversation.messages.last else { continue }
            guard !chatViewModel.isPeerBlocked(peerID) else { continue }

            let fingerprint = chatViewModel.getFingerprint(for: peerID)
            if visibleIdentities.contains(peerID.id) { continue }
            if let fingerprint, visibleIdentities.contains(fingerprint) { continue }

            let identityKey = fingerprint ?? peerID.id
            if let existing = bestByIdentity[identityKey],
               existing.lastActivity >= lastMessage.timestamp {
                continue
            }
            bestByIdentity[identityKey] = Candidate(peerID: peerID, lastActivity: lastMessage.timestamp)
        }

        return bestByIdentity.values
            .sorted { $0.lastActivity > $1.lastActivity }
            .map { candidate in
                let fingerprint = chatViewModel.getFingerprint(for: candidate.peerID)
                return RecentChatRow(
                    peerID: candidate.peerID,
                    displayName: displayName(for: candidate.peerID),
                    hasUnread: chatViewModel.hasUnreadMessages(for: candidate.peerID),
                    lastActivity: candidate.lastActivity,
                    isFavorite: !candidate.peerID.isGeoDM && chatViewModel.isFavorite(peerID: candidate.peerID),
                    isVerified: fingerprint.map { peerIdentityStore.isVerified($0) } ?? false,
                    hasAcceptedConversation: acceptance.contains(candidate.peerID, fingerprint: fingerprint),
                    hasPetname: chatViewModel.localPetname(for: candidate.peerID) != nil
                )
            }
    }

    /// GeoDM conversations resolve through the Nostr mapping —
    /// `resolveNickname` only consults mesh identity sources and would
    /// render a `nostr_…` key as an opaque `anonnost` fallback.
    private func displayName(for peerID: PeerID) -> String {
        if peerID.isGeoDM {
            return chatViewModel.geohashDisplayName(for: peerID)
        }
        return chatViewModel.resolveNickname(for: peerID)
    }

    private static func changedConversationID(_ change: ConversationChange) -> ConversationID {
        switch change {
        case .appended(let id, _),
             .updated(let id, _),
             .statusChanged(let id, _, _),
             .messageRemoved(let id, _),
             .cleared(let id),
             .removed(let id),
             .unreadChanged(let id, _):
            return id
        case .migrated(_, let to):
            return to
        }
    }

    private func buildGroupRows() -> [GroupChatRow] {
        let myFingerprint = chatViewModel.meshService.noiseIdentityFingerprint()
        return chatViewModel.groupStore.groups.map { group in
            GroupChatRow(
                peerID: group.peerID,
                name: group.name,
                memberCount: group.members.count,
                isCreator: group.creatorFingerprint == myFingerprint,
                hasUnread: chatViewModel.hasUnreadMessages(for: group.peerID)
            )
        }
    }

    private func buildGeohashPeople(acceptance: AcceptedConversations) -> [GeohashPersonRow] {
        let myHex = currentGeohashIdentityHex()
        let teleportedSet = Set(locationPresenceStore.teleportedGeo.map { $0.lowercased() })

        return chatViewModel.visibleGeohashPeople().map { person in
            let isMe = person.id == myHex
            return GeohashPersonRow(
                id: person.id,
                displayName: person.displayName,
                isMe: isMe,
                isTeleported: teleportedSet.contains(person.id.lowercased()) || (isMe && locationChannelsModel.teleported),
                isBlocked: !isMe && chatViewModel.isGeohashUserBlocked(pubkeyHexLowercased: person.id),
                hasAcceptedConversation: !isMe && acceptance.contains(PeerID(nostr_: person.id), fingerprint: nil)
            )
        }
    }

    // MARK: - Accepted conversations

    /// The accepted conversations as the row builders match them: by
    /// routing peer ID, or by fingerprint, because a conversation can be
    /// keyed by the stable Noise peer ID while the roster lists the
    /// ephemeral one.
    private struct AcceptedConversations {
        let peerIDs: Set<PeerID>
        let fingerprints: Set<String>

        func contains(_ peerID: PeerID, fingerprint: String?) -> Bool {
            if peerIDs.contains(peerID) { return true }
            guard let fingerprint else { return false }
            return fingerprints.contains(fingerprint)
        }
    }

    /// Writing in a conversation accepts it, and an accepted conversation
    /// stays accepted when it moves to the stable peer ID.
    private func noteAcceptance(from change: ConversationChange) {
        switch change {
        case .appended(.direct(let handle), let message):
            let myPeerID = chatViewModel.meshService.myPeerID
            guard message.isOwn(myPeerID: myPeerID, myGeoChatPeerID: nil) else { return }
            acceptedConversationPeerIDs.insert(handle.routingPeerID)
        case .migrated(.direct(let source), .direct(let destination)):
            guard acceptedConversationPeerIDs.contains(source.routingPeerID) else { return }
            acceptedConversationPeerIDs.insert(destination.routingPeerID)
        default:
            break
        }
    }

    /// Forgets the acceptance of conversations that no longer exist, so a
    /// panic wipe or a removed chat leaves no trace of who was a contact.
    private func pruneAcceptedConversations() {
        let kept = acceptedConversationPeerIDs.filter { peerID in
            conversations.conversationsByID[.directPeer(peerID)] != nil
        }
        if kept.count != acceptedConversationPeerIDs.count {
            acceptedConversationPeerIDs = kept
        }
    }

    private func currentGeohashIdentityHex() -> String? {
        guard case .location(let channel) = locationChannelsModel.selectedChannel,
              let identity = try? chatViewModel.idBridge.deriveIdentity(forGeohash: channel.geohash) else {
            return nil
        }

        return identity.publicKeyHex.lowercased()
    }
}
