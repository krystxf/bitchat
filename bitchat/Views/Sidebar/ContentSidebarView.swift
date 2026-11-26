//
// ContentSidebarView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// What the sidebar selects: a public channel, or a direct conversation (a
/// DM or a private group).
enum SidebarItem: Hashable {
    case mesh
    case location(geohash: String)
    case conversation(PeerID)

    init(channel: ChannelID) {
        switch channel {
        case .mesh:
            self = .mesh
        case .location(let channel):
            self = .location(geohash: channel.geohash.lowercased())
        }
    }
}

/// The main window's sidebar, as in Messages: the channels, the private
/// groups, the contacts, and everyone else under a collapsed "unknown"
/// section, so strangers and spam stay out of sight until the user asks
/// for them.
struct ContentSidebarView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @ObservedObject private var bridgeService = BridgeService.shared

    @Binding var selection: SidebarItem?

    @AppStorage("sidebar.showsUnknownPeople") private var showsUnknownPeople = false
    @State private var showsProfile = false

    var body: some View {
        let people = sidebarPeople

        List(selection: $selection) {
            Section {
                channelRows
            } header: {
                sectionHeader(Strings.channels)
            }

            if !groupRows.isEmpty {
                Section {
                    ForEach(groupRows) { group in
                        SidebarGroupRow(group: group)
                            .tag(SidebarItem.conversation(group.peerID))
                    }
                } header: {
                    sectionHeader(Strings.groups)
                }
            }

            if !people.contacts.isEmpty || people.unknown.isEmpty {
                Section {
                    if people.contacts.isEmpty {
                        PeopleEmptyRow(text: Text(verbatim: Strings.noContacts))
                    } else {
                        personRows(people.contacts)
                    }
                } header: {
                    sectionHeader(Strings.contacts)
                }
            }

            if !people.unknown.isEmpty {
                unknownSection(people.unknown)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Text(verbatim: Strings.appName))
        .toolbar {
            sidebarToolbar
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(verbatim: title)
    }

    // MARK: - Toolbar

    /// Settings, then the user's own avatar at the far end, as the App
    /// Store and Music show the account. `.primaryAction` keeps both in
    /// the sidebar's own title bar on macOS; `.navigation` renders at the
    /// start of the detail column's toolbar instead.
    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            settingsButton
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            // The avatar is the button: no glass capsule around it.
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                profileButton
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                profileButton
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            profileButton
        }
        #endif
    }

    #if os(macOS)
    private static let profileAvatarSize: CGFloat = 24
    #else
    private static let profileAvatarSize: CGFloat = 34
    #endif

    private var profileButton: some View {
        Button(action: { showsProfile = true }) {
            Label {
                Text(verbatim: Strings.profile)
            } icon: {
                InitialsAvatar(
                    name: appChromeModel.nickname,
                    peerID: appChromeModel.myPeerID,
                    size: Self.profileAvatarSize
                )
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        #endif
        .accessibilityLabel(Text(verbatim: Strings.profile))
        .help(Strings.profile)
        .sheet(isPresented: $showsProfile) {
            ProfileSheet()
                .environmentObject(appChromeModel)
                .environmentObject(verificationModel)
        }
    }

    private var settingsButton: some View {
        Button(action: { appChromeModel.presentAppInfo() }) {
            Label {
                Text(verbatim: String(localized: "app_info.tab.settings", comment: "Settings"))
            } icon: {
                Image(systemName: "gearshape")
            }
        }
        .help(String(localized: "app_info.tab.settings", comment: "Settings"))
    }

    // MARK: - Channels

    @ViewBuilder
    private var channelRows: some View {
        Label {
            Text(verbatim: "#mesh")
        } icon: {
            Image(systemName: "antenna.radiowaves.left.and.right")
        }
        .badge(meshPeopleCount)
        .tag(SidebarItem.mesh)
        .accessibilityValue(Strings.peopleCount(meshPeopleCount))

        // The channel you are in, unless it is bookmarked: then it shows
        // with the bookmarks.
        if case .location(let channel) = locationChannelsModel.selectedChannel,
           !isBookmarked(channel.geohash) {
            // Place names describe where you are, so a channel you
            // teleported to gets none.
            locationRow(
                geohash: channel.geohash,
                name: locationChannelsModel.availableChannels.contains(channel)
                    ? locationChannelsModel.locationName(for: channel.level)
                    : nil,
                systemImage: "mappin.and.ellipse"
            )
        }

        ForEach(bookmarks, id: \.self) { geohash in
            locationRow(
                geohash: geohash,
                name: bookmarkName(for: geohash),
                systemImage: "bookmark"
            )
            .onAppear { locationChannelsModel.resolveBookmarkNameIfNeeded(for: geohash) }
            .contextMenu {
                Button {
                    locationChannelsModel.toggleBookmark(geohash)
                } label: {
                    Label(Strings.removeBookmark, systemImage: "bookmark.slash")
                }
            }
        }

        Button {
            appChromeModel.isLocationChannelsSheetPresented = true
        } label: {
            Label {
                Text(verbatim: Strings.locationChannels)
            } icon: {
                Image(systemName: "number")
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    private func locationRow(geohash: String, name: String?, systemImage: String) -> some View {
        let count = participantCount(for: geohash)
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "#\(geohash.lowercased())")
                    .lineLimit(1)
                if let name, !name.isEmpty {
                    Text(verbatim: name)
                        .font(.subheadline)
                        .rowColor(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .badge(count)
        .tag(SidebarItem.location(geohash: geohash.lowercased()))
        .accessibilityElement(children: .combine)
        .accessibilityValue(Strings.peopleCount(count))
    }

    private func isBookmarked(_ geohash: String) -> Bool {
        bookmarks.contains(geohash.lowercased())
    }

    /// One number for the whole room: radio-reachable peers plus people
    /// across the bridge, as the main chat's people button counts them.
    private var meshPeopleCount: Int {
        #if DEBUG
        if SidebarSampleData.isEnabled { return SidebarSampleData.meshPeopleCount }
        #endif
        return peerListModel.reachableMeshPeerCount + bridgeService.bridgedPeerCount
    }

    // MARK: - Sources

    // Debug builds can show made-up rows instead: see `SidebarSampleData`.

    private var sidebarPeople: SidebarPeople {
        #if DEBUG
        if SidebarSampleData.isEnabled {
            return SidebarPeople(
                meshPeers: SidebarSampleData.meshRows,
                geohashPeople: SidebarSampleData.geohashPeople,
                chats: SidebarSampleData.chats
            )
        }
        #endif
        return SidebarPeople(
            meshPeers: peerListModel.meshRows,
            geohashPeople: peerListModel.geohashPeople,
            chats: peerListModel.recentChatRows,
            bridgedPeople: bridgeService.bridgedParticipants
        )
    }

    private var groupRows: [GroupChatRow] {
        #if DEBUG
        if SidebarSampleData.isEnabled { return SidebarSampleData.groupRows }
        #endif
        return peerListModel.groupRows
    }

    private var bookmarks: [String] {
        #if DEBUG
        if SidebarSampleData.isEnabled { return SidebarSampleData.bookmarks }
        #endif
        return locationChannelsModel.bookmarks
    }

    private func bookmarkName(for geohash: String) -> String? {
        #if DEBUG
        if SidebarSampleData.isEnabled { return SidebarSampleData.bookmarkNames[geohash] }
        #endif
        return locationChannelsModel.bookmarkNames[geohash]
    }

    private func participantCount(for geohash: String) -> Int {
        #if DEBUG
        if SidebarSampleData.isEnabled { return SidebarSampleData.participantCount(for: geohash) }
        #endif
        return peerListModel.participantCount(for: geohash)
    }

    // MARK: - People

    @ViewBuilder
    private func personRows(_ roster: SidebarRoster) -> some View {
        SidebarMeshPeerRows(peers: roster.meshPeers, onOpen: open)
        SidebarGeohashPeopleRows(people: roster.geohashPeople, onOpen: open)
        SidebarChatRows(chats: roster.chats, onOpen: open)
    }

    /// A collapsible section, as Mail and Files collapse theirs. iOS 16 has
    /// no collapsible sections and gets a disclosure row instead.
    @ViewBuilder
    private func unknownSection(_ roster: SidebarRoster) -> some View {
        if #available(iOS 17, macOS 14, *) {
            Section(isExpanded: $showsUnknownPeople) {
                personRows(roster)
                SidebarBridgedPeopleRows(people: roster.bridgedPeople)
            } header: {
                unknownHeader(roster)
            }
        } else {
            Section {
                DisclosureGroup(isExpanded: $showsUnknownPeople) {
                    personRows(roster)
                    SidebarBridgedPeopleRows(people: roster.bridgedPeople)
                } label: {
                    Label {
                        unknownHeader(roster)
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                    }
                }
            }
        }
    }

    /// "Unknown", how many people it holds, and a dot when one of them
    /// wrote, so a collapsed section still shows new messages.
    private func unknownHeader(_ roster: SidebarRoster) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: Strings.unknown)
            // Format style, not Text("\(count)"): locale digits and
            // grouping, and no letterless key for the catalog.
            Text(roster.count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if roster.unreadCount > 0 {
                PeopleUnreadIndicator()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.unknown)
        .accessibilityValue(unknownAccessibilityValue(roster))
    }

    private func unknownAccessibilityValue(_ roster: SidebarRoster) -> String {
        var parts = [Strings.peopleCount(roster.count)]
        if roster.unreadCount > 0 { parts.append(Strings.unread) }
        return parts.joined(separator: ", ")
    }

    private func open(_ peerID: PeerID) {
        selection = .conversation(peerID)
    }
}

private extension ContentSidebarView {
    enum Strings {
        static let appName = String(localized: "app_info.app_name", comment: "The app's name")
        static let profile = String(localized: "profile.title", defaultValue: "Profile", comment: "Title of the sheet where the user edits their own profile, and the label of the sidebar button that opens it")
        static let channels = String(localized: "sidebar.section.channels", defaultValue: "Channels", comment: "Sidebar section header above the public channels")
        static let groups = String(localized: "sidebar.section.groups", defaultValue: "Groups", comment: "Sidebar section header above the private groups the user belongs to")
        static let contacts = String(localized: "sidebar.section.contacts", defaultValue: "Contacts", comment: "Sidebar section header above people the user knows: favorites, verified people and accepted conversations")
        static let noContacts = String(localized: "sidebar.contacts.empty", defaultValue: "Favorites and people you message appear here.", comment: "Shown in the sidebar's contacts section when the user has no contacts yet")
        static let unknown = String(localized: "sidebar.unknown.title", defaultValue: "Unknown", comment: "Collapsed sidebar group holding people the user does not know yet and their message requests")
        static let locationChannels = String(localized: "app_info.settings.location_channels.title", defaultValue: "Location Channels", comment: "Section header (uppercase) for location channel settings such as proof of work") + "…"
        static let removeBookmark = String(localized: "location_channels.accessibility.remove_bookmark", comment: "Accessibility action name for removing a channel bookmark")
        static let unread = String(localized: "mesh_peers.state.unread", comment: "State label for a peer with unread private messages")

        static func peopleCount(_ count: Int) -> String {
            String(
                format: String(localized: "content.accessibility.people_count", comment: "Accessibility label announcing number of people in header"),
                locale: .current,
                count
            )
        }
    }
}
