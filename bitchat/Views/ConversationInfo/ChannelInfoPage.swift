//
// ChannelInfoPage.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// The info page of the public channel on screen, #mesh or a location
/// channel: its name, place and head count, notices, bookmark and share
/// for a location channel, the way to the other channels, the background,
/// and the people in the channel.
struct ChannelInfoPage: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var boardAlertsModel: BoardAlertsModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @ObservedObject private var bridgeService = BridgeService.shared
    @ThemedPalette private var palette

    @Binding var background: ChatBackgroundOption
    let backgroundKey: ComposerDraftStore.Key

    @State private var pendingShareGeohash: String?
    @State private var showsSharePrecisionWarning = false
    @State private var activeSharePayload: ChannelSharePayload?

    var body: some View {
        let channel = locationChannelsModel.selectedChannel
        let roster = ChannelRoster(
            channel: channel,
            meshRows: peerListModel.meshRows,
            geohashPeople: peerListModel.geohashPeople,
            bridged: bridgeService.bridgedParticipants
        )
        let layout = ConversationInfoPolicy.layout(for: channel.isLocation ? .locationChannel : .meshChannel)

        ConversationInfoPage(
            title: Text(verbatim: ChannelTitle.text(for: channel)),
            subtitle: subtitle(for: channel, roster: roster),
            avatar: { avatar(for: channel) },
            quickActions: {
                ForEach(layout.quickActions, id: \.self) { action in
                    quickAction(action, channel: channel)
                }
            },
            sections: {
                Section {
                    ForEach(layout.rows, id: \.self) { row in
                        self.row(row, roster: roster)
                    }
                }
            }
        )
        .confirmationDialog(
            String(localized: "channel.share.precision_warning.title", defaultValue: "share a precise location channel?", comment: "Title of the confirmation before sharing a neighborhood-or-finer geohash invite"),
            isPresented: $showsSharePrecisionWarning,
            titleVisibility: .visible
        ) {
            Button(String(localized: "channel.share.precision_warning.confirm", defaultValue: "share anyway", comment: "Confirms sharing a fine-precision location channel after the OpSec warning")) {
                if let geohash = pendingShareGeohash {
                    activeSharePayload = ChannelSharePayload(text: ChannelShare.payload(forGeohash: geohash))
                }
                pendingShareGeohash = nil
            }
            Button("common.cancel", role: .cancel) {
                pendingShareGeohash = nil
            }
        } message: {
            Text(String(localized: "channel.share.precision_warning.message", defaultValue: "this channel covers a small area. an invite sent over sms or imessage is visible to the carrier and both handsets — it discloses interest in that place, not only that someone uses bitchat.", comment: "Body of the confirmation before sharing a fine-precision geohash invite"))
        }
        .sheet(item: $activeSharePayload) { payload in
            ShareActivityView(text: payload.text)
        }
    }

    // MARK: - Header

    private func avatar(for channel: ChannelID) -> some View {
        switch channel {
        case .mesh:
            return ConversationGlyphAvatar(systemImage: "antenna.radiowaves.left.and.right", color: ChannelTitle.meshBlue)
        case .location:
            return ConversationGlyphAvatar(systemImage: "mappin.and.ellipse", color: palette.locationAccent)
        }
    }

    /// The place, when the channel has a name for it, and the head count.
    private func subtitle(for channel: ChannelID, roster: ChannelRoster) -> String {
        let count = ConversationInfoStrings.peopleCount(roster.count)
        guard let place = placeName(for: channel) else { return count }
        return "\(place) · \(count)"
    }

    private func placeName(for channel: ChannelID) -> String? {
        guard case .location(let location) = channel else { return nil }
        // Place names describe where I am, so a channel I teleported to
        // shows only a bookmark's saved name.
        let name = locationChannelsModel.availableChannels.contains(location)
            ? locationChannelsModel.locationName(for: location.level)
            : locationChannelsModel.bookmarkNames[location.geohash.lowercased()]
        return name?.trimmedOrNilIfEmpty
    }

    // MARK: - Quick actions

    @ViewBuilder
    private func quickAction(_ action: ConversationInfoPolicy.QuickAction, channel: ChannelID) -> some View {
        switch action {
        case .notices:
            ConversationQuickAction(title: Strings.notices, systemImage: "pin") {
                presentNotices(for: channel)
            }
        case .bookmark:
            if case .location(let location) = channel {
                let isBookmarked = locationChannelsModel.isBookmarked(location.geohash)
                ConversationQuickAction(
                    title: Strings.bookmark,
                    systemImage: "bookmark",
                    isOn: isBookmarked,
                    accessibilityLabel: isBookmarked ? Strings.removeBookmark : Strings.addBookmark
                ) {
                    locationChannelsModel.toggleBookmark(location.geohash)
                }
            }
        case .share:
            if case .location(let location) = channel {
                ConversationQuickAction(
                    title: Strings.share,
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: Strings.shareChannel
                ) {
                    requestShare(forGeohash: location.geohash)
                }
            }
        case .favorite, .verify, .createGroup, .addPeople:
            // Not offered for a channel (see ConversationInfoPolicy).
            EmptyView()
        }
    }

    /// Opens the notices on the channel's board and marks them seen, as
    /// the pinned notices bar does.
    private func presentNotices(for channel: ChannelID) {
        var scopes: Set<String> = [""]
        switch channel {
        case .location(let location):
            scopes.insert(location.geohash)
        case .mesh:
            if let building = locationChannelsModel.currentBuildingGeohash {
                scopes.insert(building)
            }
        }
        boardAlertsModel.markSeen(forScopes: scopes)
        appChromeModel.presentNotices()
    }

    private func requestShare(forGeohash geohash: String) {
        if ChannelShare.shouldWarn(forGeohash: geohash) {
            pendingShareGeohash = geohash
            showsSharePrecisionWarning = true
        } else {
            activeSharePayload = ChannelSharePayload(text: ChannelShare.payload(forGeohash: geohash))
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ row: ConversationInfoPolicy.Row, roster: ChannelRoster) -> some View {
        switch row {
        case .background:
            ConversationMessageColorPickerRow(conversationKey: backgroundKey)
            ChatBackgroundPickerRow(conversationKey: backgroundKey, selection: $background)
        case .people:
            ConversationInfoLinkRow(title: Strings.people) {
                LabeledContent {
                    Text(roster.count, format: .number)
                        .monospacedDigit()
                } label: {
                    Label(Strings.people, systemImage: "person.2")
                }
            } destination: { close in
                ChannelPeopleList(onOpenConversation: close)
                    .environmentObject(conversationUIModel)
                    .environmentObject(peerListModel)
                    .environmentObject(locationChannelsModel)
                    .environmentObject(privateConversationModel)
            }
        case .members:
            // Not offered for a channel (see ConversationInfoPolicy).
            EmptyView()
        }
    }
}

/// Who is in a public channel: the people I can reach on the mesh and
/// across the bridge in #mesh, or those seen in a location channel. Not me.
/// People I blocked stay listed, so their row can unblock them.
struct ChannelRoster: Equatable {
    var meshPeers: [MeshPeerRow] = []
    var geohashPeople: [GeohashPersonRow] = []
    var bridged: [BridgeService.BridgedParticipant] = []

    var count: Int { meshPeers.count + geohashPeople.count + bridged.count }
    var isEmpty: Bool { count == 0 }

    init(
        channel: ChannelID,
        meshRows: [MeshPeerRow],
        geohashPeople: [GeohashPersonRow],
        bridged: [BridgeService.BridgedParticipant]
    ) {
        switch channel {
        case .mesh:
            // Offline favorites are in the mesh roster too, but not in the
            // room.
            meshPeers = meshRows.filter { !$0.isMe && ($0.isConnected || $0.isReachable) }
            self.bridged = bridged
        case .location:
            // Those physically here first, then those who teleported in.
            let people = geohashPeople.filter { !$0.isMe }
            self.geohashPeople = people.filter { !$0.isTeleported } + people.filter(\.isTeleported)
        }
    }
}

/// The people of the channel on screen. A row opens a private chat with
/// the person, and its context menu favorites, blocks or unblocks them or
/// starts a group with them. People across the bridge have no route for
/// either yet.
private struct ChannelPeopleList: View {
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @ObservedObject private var bridgeService = BridgeService.shared

    /// Closes the list when a chat opens in its place.
    let onOpenConversation: () -> Void

    var body: some View {
        let roster = ChannelRoster(
            channel: locationChannelsModel.selectedChannel,
            meshRows: peerListModel.meshRows,
            geohashPeople: peerListModel.geohashPeople,
            bridged: bridgeService.bridgedParticipants
        )
        List {
            if roster.isEmpty {
                PeopleEmptyRow()
            }
            ForEach(roster.meshPeers) { peer in
                personButton(name: peer.displayName, peerID: peer.peerID, presence: peer.presence, isBlocked: peer.isBlocked) {
                    privateConversationModel.startConversation(with: peer.peerID)
                }
                .personActions(for: PersonActionTarget(meshPeer: peer, model: conversationUIModel))
            }
            ForEach(roster.geohashPeople) { person in
                personButton(name: person.displayName, peerID: PeerID(nostr_: person.id), presence: person.presence, isBlocked: person.isBlocked) {
                    privateConversationModel.startGeohashConversation(withPubkeyHex: person.id)
                }
                .personActions(for: PersonActionTarget(geohashPerson: person))
            }
            ForEach(roster.bridged) { person in
                personRow(name: person.displayName, peerID: PeerID(bridge: person.pubkey), presence: .bridged, isBlocked: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(person.displayName), \(PersonPresence.bridged.label)"))
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle(Text(verbatim: Strings.people))
        .personActionsHost()
    }

    private func personButton(
        name: String,
        peerID: PeerID,
        presence: PersonPresence,
        isBlocked: Bool,
        open: @escaping () -> Void
    ) -> some View {
        Button {
            open()
            onOpenConversation()
        } label: {
            personRow(name: name, peerID: peerID, presence: presence, isBlocked: isBlocked)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ([name, presence.label] + (isBlocked ? [Strings.blocked] : [])).joined(separator: ", ")))
        .accessibilityHint(Text(verbatim: Strings.openDMHint))
        .accessibilityAddTraits(.isButton)
    }

    private func personRow(name: String, peerID: PeerID, presence: PersonPresence, isBlocked: Bool) -> some View {
        PeopleRow(subtitle: presence.label) {
            SidebarPersonAvatar(name: name, peerID: peerID, presence: presence)
        } title: {
            PeopleRowName(name: name)
        } accessories: {
            if isBlocked {
                Image(systemName: "nosign")
                    .foregroundColor(.red)
                    .help(Strings.blocked)
            }
        }
    }
}

/// A row that opens a page of its own: pushed onto the navigation stack on
/// iOS; a sheet on macOS, where the info page sits in an inspector with no
/// navigation stack.
struct ConversationInfoLinkRow<Label: View, Destination: View>: View {
    let title: String
    let label: Label
    /// Builds the page. It gets the action that closes it.
    let destination: (@escaping () -> Void) -> Destination

    #if os(macOS)
    @State private var isPresented = false
    #endif

    init(
        title: String,
        @ViewBuilder label: () -> Label,
        @ViewBuilder destination: @escaping (@escaping () -> Void) -> Destination
    ) {
        self.title = title
        self.label = label()
        self.destination = destination
    }

    var body: some View {
        #if os(iOS)
        NavigationLink {
            // A chat opening in its place replaces the pages on its own.
            destination({})
        } label: {
            label
        }
        #else
        Button {
            isPresented = true
        } label: {
            HStack {
                label
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            destination({ isPresented = false })
                .frame(minWidth: 380, minHeight: 440)
                .sheetChrome(title: Text(verbatim: title), onClose: { isPresented = false })
        }
        #endif
    }
}

/// "#mesh", or "#<geohash>" in a location channel. A channel name, not
/// localized.
enum ChannelTitle {
    static func text(for channel: ChannelID) -> String {
        switch channel {
        case .mesh: return "#mesh"
        case .location(let channel): return "#\(channel.geohash)"
        }
    }

    /// The mesh channel's blue, as the people count in the title bar used.
    static let meshBlue = Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
}

private enum Strings {
    static let notices = String(localized: "content.accessibility.notices", comment: "Menu action for notices")
    static let bookmark = String(localized: "conversation_info.action.bookmark", defaultValue: "Bookmark", comment: "Short label of the button on a location channel's details page that bookmarks the channel or removes the bookmark")
    static let addBookmark = String(localized: "location_channels.accessibility.add_bookmark", comment: "Accessibility action name for bookmarking a channel")
    static let removeBookmark = String(localized: "location_channels.accessibility.remove_bookmark", comment: "Accessibility action name for removing a channel bookmark")
    static let share = String(localized: "conversation_info.action.share", defaultValue: "Share", comment: "Short label of the button on a location channel's details page that shares an invite to the channel")
    static let shareChannel = String(localized: "channel.share.action", defaultValue: "share channel", comment: "Accessibility label for sharing the active location channel")
    static let people = String(localized: "conversation_info.row.people", defaultValue: "People", comment: "Row on a channel's details page, and the title of the page it opens, listing the people in the channel")
    static let blocked = String(localized: "mesh_peers.state.blocked", comment: "State label for a blocked peer")
    static let openDMHint = String(localized: "mesh_peers.accessibility.open_dm_hint", comment: "Accessibility hint on a peer row explaining activation opens a private chat")
}
