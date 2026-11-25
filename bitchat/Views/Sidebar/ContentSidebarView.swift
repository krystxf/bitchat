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

/// The main window's sidebar, as in Messages: the channels, the contacts,
/// and everyone else under a collapsed "unknown" group, so strangers and
/// spam stay out of sight until the user asks for them.
struct ContentSidebarView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @ObservedObject private var bridgeService = BridgeService.shared

    @Binding var selection: SidebarItem?
    @Binding var showVerifySheet: Bool

    @AppStorage("sidebar.showsUnknownPeople") private var showsUnknownPeople = false

    var body: some View {
        let people = SidebarPeople(
            meshPeers: peerListModel.meshRows,
            geohashPeople: peerListModel.geohashPeople,
            chats: peerListModel.recentChatRows,
            bridgedPeople: bridgeService.bridgedParticipants
        )

        List(selection: $selection) {
            Section {
                channelRows
            } header: {
                Text(verbatim: Strings.channels)
            }

            if !people.contacts.isEmpty || people.unknown.isEmpty {
                Section {
                    if people.contacts.isEmpty {
                        PeopleEmptyRow()
                    } else {
                        personRows(people.contacts)
                    }
                } header: {
                    Text(verbatim: Strings.contacts)
                }
            }

            if !people.unknown.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsUnknownPeople) {
                        personRows(people.unknown)
                        SidebarBridgedPeopleRows(people: people.unknown.bridgedPeople)
                    } label: {
                        unknownLabel(people.unknown)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Text(verbatim: Strings.appName))
        .toolbar {
            // .primaryAction keeps the gear in the sidebar's own title bar on
            // macOS, next to the QR button; .navigation renders at the start
            // of the detail column's toolbar instead.
            ToolbarItem(placement: .primaryAction) {
                settingsButton
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showVerifySheet = true
                } label: {
                    Label(Strings.verification, systemImage: "qrcode")
                }
                .help(Strings.verificationHelp)
            }
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

        ForEach(locationChannelsModel.bookmarks, id: \.self) { geohash in
            locationRow(
                geohash: geohash,
                name: locationChannelsModel.bookmarkNames[geohash],
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

        ForEach(peerListModel.groupRows) { group in
            SidebarGroupRow(group: group)
                .tag(SidebarItem.conversation(group.peerID))
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
        let count = peerListModel.participantCount(for: geohash)
        return Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "#\(geohash.lowercased())")
                    .lineLimit(1)
                if let name, !name.isEmpty {
                    Text(verbatim: name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        locationChannelsModel.bookmarks.contains(geohash.lowercased())
    }

    /// One number for the whole room: radio-reachable peers plus people
    /// across the bridge, as the main chat's people button counts them.
    private var meshPeopleCount: Int {
        peerListModel.reachableMeshPeerCount + bridgeService.bridgedPeerCount
    }

    // MARK: - People

    @ViewBuilder
    private func personRows(_ roster: SidebarRoster) -> some View {
        SidebarMeshPeerRows(peers: roster.meshPeers, onOpen: open)
        SidebarGeohashPeopleRows(people: roster.geohashPeople, onOpen: open)
        SidebarChatRows(chats: roster.chats, onOpen: open)
    }

    private func unknownLabel(_ roster: SidebarRoster) -> some View {
        Label {
            HStack(spacing: 8) {
                Text(verbatim: Strings.unknown)
                Spacer(minLength: 8)
                if roster.unreadCount > 0 {
                    PeopleUnreadIndicator()
                        .font(.subheadline)
                }
                // Format style, not Text("\(count)"): locale digits and
                // grouping, and no letterless key for the catalog.
                Text(roster.count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "person.crop.circle.badge.questionmark")
        }
        #if os(macOS)
        // A macOS outline row toggles only from its disclosure triangle;
        // the whole label shows or hides the group, as the iOS row does.
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { showsUnknownPeople.toggle() }
        }
        #endif
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
        static let channels = String(localized: "sidebar.section.channels", defaultValue: "channels", comment: "Sidebar section header above the public channels and private groups")
        static let contacts = String(localized: "sidebar.section.contacts", defaultValue: "contacts", comment: "Sidebar section header above people the user knows: favorites, verified people and accepted conversations")
        static let unknown = String(localized: "sidebar.unknown.title", defaultValue: "unknown", comment: "Collapsed sidebar group holding people the user does not know yet and their message requests")
        static let locationChannels = String(localized: "content.accessibility.location_channels", comment: "Accessibility label for the location channels button") + "…"
        static let removeBookmark = String(localized: "location_channels.accessibility.remove_bookmark", comment: "Accessibility action name for removing a channel bookmark")
        static let verification = String(localized: "content.accessibility.verification", comment: "Accessibility label for the verification QR button")
        static let verificationHelp = String(localized: "content.help.verification", comment: "Help text for verification button")
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
