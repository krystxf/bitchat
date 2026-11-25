import SwiftUI

/// Native title bar for the main chat: the channel's name as a button that
/// opens the channel's info page, with my nickname and the head count under
/// it. Notices, bookmark, share, the channel list, the background and the
/// people live on that page, so the title bar keeps only two indicators:
///
/// - The orange envelope for an unread private chat. In a phone's chat the
///   sidebar is out of sight, so it is the only sign that someone wrote,
///   and one tap opens the chat.
/// - The courier figure while this device carries sealed messages for
///   friends. It is status, not a control, and it shows only then.
struct ContentHeaderToolbar: ViewModifier {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @ObservedObject private var bridgeService = BridgeService.shared
    @ThemedPalette private var palette

    @Binding var backgroundOption: ChatBackgroundOption

    /// Courier envelopes this device is carrying for offline third parties.
    @State private var carriedMailCount = 0
    /// The channel's info page, opened from the title.
    @State private var showsInfo = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(ChannelTitle.text(for: locationChannelsModel.selectedChannel))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .conversationTitleBar(hidesNativeTitle: true)
            .conversationInfo(isPresented: $showsInfo) {
                ChannelInfoPage(background: $backgroundOption, backgroundKey: backgroundKey)
            }
            .onReceive(CourierStore.shared.$carriedCount) { count in
                carriedMailCount = count
            }
            .onAppear {
                locationChannelsModel.refreshMeshChannelsIfNeeded()
            }
            .onChange(of: locationChannelsModel.selectedChannel) { _ in
                locationChannelsModel.refreshMeshChannelsIfNeeded()
                // The page belongs to the channel it was opened from.
                showsInfo = false
            }
            .onChange(of: locationChannelsModel.permissionState) { _ in
                locationChannelsModel.refreshMeshChannelsIfNeeded()
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ConversationTitleToolbarItem(
            title: Text(verbatim: ChannelTitle.text(for: locationChannelsModel.selectedChannel)),
            subtitle: subtitle
        ) {
            showsInfo.toggle()
        }
        if carriedMailCount > 0 || appChromeModel.hasUnreadPrivateMessages {
            ToolbarItemGroup(placement: .primaryAction) {
                if carriedMailCount > 0 {
                    carriedMailIndicator
                }
                if appChromeModel.hasUnreadPrivateMessages {
                    unreadPrivateChatButton
                }
            }
        }
    }

    /// "@nickname · 3 people": who I post as, and who hears it.
    private var subtitle: String {
        let roster = ChannelRoster(
            channel: locationChannelsModel.selectedChannel,
            meshRows: peerListModel.meshRows,
            geohashPeople: peerListModel.geohashPeople,
            bridged: bridgeService.bridgedParticipants
        )
        return "@\(appChromeModel.nickname) · \(ConversationInfoStrings.peopleCount(roster.count))"
    }

    private var backgroundKey: ComposerDraftStore.Key {
        ComposerDraftStore.Key.from(
            peerID: nil,
            fingerprint: nil,
            channel: locationChannelsModel.selectedChannel
        )
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
        .help(
            String(localized: "content.accessibility.open_unread_private_chat", comment: "Accessibility label for the unread private chat button")
        )
    }
}
