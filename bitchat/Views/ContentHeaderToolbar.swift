import SwiftUI

/// Native title bar for the main chat. The channel is the navigation title,
/// the nickname its subtitle, and the header's controls are toolbar buttons.
/// The title opens a menu with the channel actions (switch, bookmark, share).
/// Also hosts the notices sheet and the share dialogs those controls
/// present; the location channels sheet lives at the root, because the
/// sidebar opens it too.
struct ContentHeaderToolbar: ViewModifier {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var boardAlertsModel: BoardAlertsModel
    @ObservedObject private var bridgeService = BridgeService.shared
    @ThemedPalette private var palette

    /// Reveals the people in the sidebar.
    let onShowPeople: () -> Void
    @Binding var backgroundOption: ChatBackgroundOption

    /// Courier envelopes this device is carrying for offline third parties.
    @State private var carriedMailCount = 0

    @State private var pendingShareGeohash: String?
    @State private var showSharePrecisionWarning = false
    @State private var activeSharePayload: ChannelSharePayload?

    func body(content: Content) -> some View {
        content
            .navigationTitle(channelTitle)
            .modifier(NavigationSubtitle(text: "@\(appChromeModel.nickname)"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarTitleMenu { channelMenu }
            .toolbar { toolbarContent }
            .onReceive(CourierStore.shared.$carriedCount) { count in
                carriedMailCount = count
            }
            .sheet(
                isPresented: $appChromeModel.isNoticesSheetPresented,
                onDismiss: { appChromeModel.noticesSheetPrefersGeoTab = false }
            ) {
                NoticesView(
                    senderNickname: appChromeModel.nickname,
                    board: appChromeModel.boardManager,
                    initialTab: initialNoticesTab
                )
                .environmentObject(locationChannelsModel)
            }
            .onAppear {
                locationChannelsModel.refreshMeshChannelsIfNeeded()
            }
            .onChange(of: locationChannelsModel.selectedChannel) { _ in
                locationChannelsModel.refreshMeshChannelsIfNeeded()
            }
            .onChange(of: locationChannelsModel.permissionState) { _ in
                locationChannelsModel.refreshMeshChannelsIfNeeded()
            }
            .confirmationDialog(
                String(localized: "channel.share.precision_warning.title", defaultValue: "share a precise location channel?", comment: "Title of the confirmation before sharing a neighborhood-or-finer geohash invite"),
                isPresented: $showSharePrecisionWarning,
                titleVisibility: .visible
            ) {
                Button(String(localized: "channel.share.precision_warning.confirm", defaultValue: "share anyway", comment: "Confirms sharing a fine-precision location channel after the OpSec warning")) {
                    if let gh = pendingShareGeohash {
                        activeSharePayload = ChannelSharePayload(text: ChannelShare.payload(forGeohash: gh))
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if carriedMailCount > 0 {
                carriedMailIndicator
            }
            if appChromeModel.hasUnreadPrivateMessages {
                unreadPrivateChatButton
            }
            channelButton
            peopleButton
        }
    }

    /// Channel switcher. A click opens the location channels sheet; its menu
    /// adds bookmark and share in a location channel. The title menu holds
    /// the same actions, but macOS shows no menu on a window title, so the
    /// button is the way in there.
    private var channelButton: some View {
        Menu {
            channelMenu
        } label: {
            Label {
                Text(verbatim: String(localized: "content.accessibility.location_channels", comment: "Accessibility label for the location channels button"))
            } icon: {
                Image(systemName: "number")
            }
        } primaryAction: {
            appChromeModel.isLocationChannelsSheetPresented = true
        }
        .help(String(localized: "content.accessibility.location_channels", comment: "Accessibility label for the location channels button"))
    }

    /// The title's menu: everything about the current channel.
    @ViewBuilder
    private var channelMenu: some View {
        Button {
            appChromeModel.isLocationChannelsSheetPresented = true
        } label: {
            Label {
                Text(verbatim: String(localized: "content.accessibility.location_channels", comment: "Accessibility label for the location channels button"))
            } icon: {
                Image(systemName: "number")
            }
        }

        Button(action: presentNotices) {
            Label {
                Text(verbatim: String(localized: "content.accessibility.notices", comment: "Menu action for notices").lowercased())
            } icon: {
                Image(systemName: "pin")
            }
        }

        ChatBackgroundPickerMenu(
            conversationKey: ComposerDraftStore.Key.from(
                peerID: nil,
                fingerprint: nil,
                channel: locationChannelsModel.selectedChannel
            ),
            selection: $backgroundOption
        )

        if case .location(let channel) = locationChannelsModel.selectedChannel {
            Button {
                locationChannelsModel.toggleBookmark(channel.geohash)
            } label: {
                Label {
                    Text(verbatim: String(
                        format: String(localized: "content.accessibility.toggle_bookmark", comment: "Accessibility label for toggling a geohash bookmark"),
                        locale: .current,
                        channel.geohash
                    ))
                } icon: {
                    Image(systemName: locationChannelsModel.isBookmarked(channel.geohash) ? "bookmark.fill" : "bookmark")
                }
            }

            Button {
                requestHeaderShare(forGeohash: channel.geohash)
            } label: {
                Label {
                    Text(verbatim: String(localized: "channel.share.action", defaultValue: "share channel", comment: "Accessibility label for sharing the active location channel"))
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var carriedMailIndicator: some View {
        Image(systemName: "figure.walk")
            .foregroundColor(palette.secondary)
            .accessibilityLabel(
                String(
                    format: String(localized: "content.accessibility.carrying_mail", defaultValue: "Carrying %lld sealed messages for friends", comment: "Accessibility label for the courier mail indicator"),
                    locale: .current,
                    carriedMailCount
                )
            )
            .help(
                String(localized: "content.header.carrying_mail", defaultValue: "Carrying sealed messages for friends to deliver", comment: "Tooltip for the courier mail indicator")
            )
    }

    private var unreadPrivateChatButton: some View {
        Button(action: { appChromeModel.openMostRelevantPrivateChat() }) {
            Image(systemName: "envelope.fill")
                .foregroundColor(.orange)
        }
        .accessibilityLabel(
            String(localized: "content.accessibility.open_unread_private_chat", comment: "Accessibility label for the unread private chat button")
        )
    }

    private func presentNotices() {
        var scopes: Set<String> = [""]
        if let geoScope = noticesGeoScope { scopes.insert(geoScope) }
        boardAlertsModel.markSeen(forScopes: scopes)
        appChromeModel.presentNotices()
    }

    private var peopleButton: some View {
        let countAndColor = channelPeopleCountAndColor()
        let peopleCount: Int = {
            if case .location = locationChannelsModel.selectedChannel {
                return peerListModel.visibleGeohashPeerCount
            }
            // One number for the whole room: radio-reachable peers plus
            // people across the bridge (visible via carriers even while
            // this device's own bridge is off). The sheet breaks it down.
            return countAndColor.0 + bridgeService.bridgedPeerCount
        }()

        return Button(action: onShowPeople) {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                // Format style, not Text("\(count)"): same locale digits
                // and grouping, and no letterless key for Xcode's
                // localization export to add back to the catalog.
                Text(peopleCount, format: .number)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
            .foregroundColor(countAndColor.1)
        }
        .accessibilityLabel(
            String(
                format: String(localized: "content.accessibility.people_count", comment: "Accessibility label announcing number of people in header"),
                locale: .current,
                peopleCount
            )
        )
        // Connected-vs-nobody is otherwise encoded only in the icon's
        // color; say it. With a live bridge, also say who's across it.
        .accessibilityValue(
            showBridgedPeerCount
            ? String(
                format: String(localized: "content.accessibility.bridged_count", defaultValue: "%lld more people across the bridge", comment: "Accessibility value announcing the number of people reachable via the mesh bridge"),
                locale: .current,
                bridgeService.bridgedPeerCount
            )
            : (headerPeersReachable
                ? String(localized: "content.accessibility.peers_connected", comment: "Accessibility value when peers are reachable")
                : String(localized: "content.accessibility.peers_none", comment: "Accessibility value when no peers are reachable"))
        )
    }

    private func requestHeaderShare(forGeohash geohash: String) {
        if ChannelShare.shouldWarn(forGeohash: geohash) {
            pendingShareGeohash = geohash
            showSharePrecisionWarning = true
        } else {
            activeSharePayload = ChannelSharePayload(text: ChannelShare.payload(forGeohash: geohash))
        }
    }
}

/// `.navigationSubtitle` exists on macOS 11+ and iOS 26+; older iOS shows
/// the title alone.
private struct NavigationSubtitle: ViewModifier {
    let text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.navigationSubtitle(text)
        #elseif compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(text)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private extension ContentHeaderToolbar {
    /// "#mesh", or "#<geohash>" in a location channel.
    var channelTitle: String {
        switch locationChannelsModel.selectedChannel {
        case .mesh: return "#mesh"
        case .location(let channel): return "#\(channel.geohash)"
        }
    }

    /// The bridged-people count belongs to the mesh channel only.
    var showBridgedPeerCount: Bool {
        if case .location = locationChannelsModel.selectedChannel { return false }
        return bridgeService.bridgedPeerCount > 0
    }

    /// Open the notices sheet on the tab matching the current channel: the
    /// geohash channel's notices, or the mesh-local board in mesh chat. An
    /// explicit geo-tab request (the "notes left here" hint) wins.
    var initialNoticesTab: NoticesView.Tab {
        if appChromeModel.noticesSheetPrefersGeoTab {
            return .geo
        }
        if case .location = locationChannelsModel.selectedChannel {
            return .geo
        }
        return .mesh
    }

    /// The geo scope the notices sheet would open on: the selected location
    /// channel, or the device's building geohash when chatting on mesh.
    var noticesGeoScope: String? {
        if case .location(let channel) = locationChannelsModel.selectedChannel {
            return channel.geohash
        }
        return locationChannelsModel.currentBuildingGeohash
    }

    /// Whether anyone is actually reachable on the current channel — the
    /// state the count icon's color encodes visually.
    var headerPeersReachable: Bool {
        switch locationChannelsModel.selectedChannel {
        case .location:
            return peerListModel.visibleGeohashPeerCount > 0
        case .mesh:
            return peerListModel.connectedMeshPeerCount > 0
        }
    }

    func channelPeopleCountAndColor() -> (Int, Color) {
        switch locationChannelsModel.selectedChannel {
        case .location:
            let count = peerListModel.visibleGeohashPeerCount
            return (count, count > 0 ? palette.locationAccent : palette.secondary)
        case .mesh:
            let meshBlue = Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
            let color: Color = peerListModel.connectedMeshPeerCount > 0 ? meshBlue : palette.secondary
            return (peerListModel.reachableMeshPeerCount, color)
        }
    }
}
