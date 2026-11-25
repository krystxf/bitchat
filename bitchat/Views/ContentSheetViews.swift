import BitFoundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentPeopleSheetModalPresentationState {
    var isImagePreviewPresented = false
    var isVerificationSheetPresented = false
    var legacyPrivateMediaConsentRequest: LegacyPrivateMediaConsentRequest? = nil
    var isVoiceAlertPresented = false
    var isMediaPickerPresented = false

    var hasPresentation: Bool {
        isImagePreviewPresented
            || isVerificationSheetPresented
            || legacyPrivateMediaConsentRequest != nil
            || isVoiceAlertPresented
            || isMediaPickerPresented
    }
}

struct ContentPeopleSheetView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @Environment(\.scenePhase) private var scenePhase

    @Binding var showSidebar: Bool
    @Binding var messageText: String
    @Binding var selectedMessageSender: String?
    @Binding var selectedMessageSenderID: PeerID?
    @Binding var imagePreviewURL: URL?
    @Binding var windowCountPublic: Int
    @Binding var windowCountPrivate: [PeerID: Int]
    @Binding var isAtBottomPrivate: Bool
    var isTextFieldFocused: FocusState<Bool>.Binding
    @ObservedObject var voiceRecordingVM: VoiceRecordingViewModel
    @Binding var autocompleteDebounceTimer: Timer?
    @State private var showVerifySheet = false
    @ThemedPalette private var palette

    let onSendMessage: () -> Void

    #if os(iOS)
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSourceType: UIImagePickerController.SourceType
    #endif

    private func modalPresentationState(
        includingVoiceAlert: Bool
    ) -> ContentPeopleSheetModalPresentationState {
        #if os(iOS)
        let isMediaPickerPresented = showImagePicker
        #else
        // The macOS open panel is window-modal and needs no flag.
        let isMediaPickerPresented = false
        #endif

        return ContentPeopleSheetModalPresentationState(
            isImagePreviewPresented: imagePreviewURL != nil,
            isVerificationSheetPresented: showVerifySheet,
            legacyPrivateMediaConsentRequest:
                conversationUIModel.legacyPrivateMediaConsentRequest,
            isVoiceAlertPresented: includingVoiceAlert && voiceRecordingVM.showAlert,
            isMediaPickerPresented: isMediaPickerPresented
        )
    }

    private var hasModalPresentation: Bool {
        modalPresentationState(includingVoiceAlert: true).hasPresentation
    }

    /// The voice alert cannot defer to itself: its own binding must keep
    /// reporting `true` while it is the presented modal.
    private var hasModalPresentationBesidesVoiceAlert: Bool {
        modalPresentationState(includingVoiceAlert: false).hasPresentation
    }

    private var bluetoothAlertBinding: Binding<Bool> {
        Binding(
            get: {
                scenePhase == .active
                    && appChromeModel.showBluetoothAlert
                    && !hasModalPresentation
            },
            set: { isPresented in
                guard !isPresented,
                      scenePhase == .active,
                      !hasModalPresentation else {
                    return
                }
                appChromeModel.showBluetoothAlert = false
            }
        )
    }

    /// Voice recording happens inside this sheet, so its error alert must
    /// present from here as well: the root copy defers whenever this sheet
    /// is up, exactly like the Bluetooth alert above. Presenting from the
    /// root instead would force-dismiss the sheet and end the conversation.
    private var voiceAlertBinding: Binding<Bool> {
        Binding(
            get: {
                scenePhase == .active
                    && voiceRecordingVM.showAlert
                    && !hasModalPresentationBesidesVoiceAlert
            },
            set: { isPresented in
                guard !isPresented,
                      scenePhase == .active,
                      !hasModalPresentationBesidesVoiceAlert else {
                    return
                }
                voiceRecordingVM.showAlert = false
            }
        )
    }

    var body: some View {
        let legacyConsentRequest = conversationUIModel.legacyPrivateMediaConsentRequest
        NavigationStack {
            Group {
                if privateConversationModel.selectedPeerID != nil {
                    #if os(iOS)
                    ContentPrivateChatSheetView(
                        showSidebar: $showSidebar,
                        messageText: $messageText,
                        selectedMessageSender: $selectedMessageSender,
                        selectedMessageSenderID: $selectedMessageSenderID,
                        imagePreviewURL: $imagePreviewURL,
                        windowCountPublic: $windowCountPublic,
                        windowCountPrivate: $windowCountPrivate,
                        isAtBottomPrivate: $isAtBottomPrivate,
                        isTextFieldFocused: isTextFieldFocused,
                        voiceRecordingVM: voiceRecordingVM,
                        autocompleteDebounceTimer: $autocompleteDebounceTimer,
                        onSendMessage: onSendMessage,
                        showImagePicker: $showImagePicker,
                        imagePickerSourceType: $imagePickerSourceType
                    )
                    #else
                    ContentPrivateChatSheetView(
                        showSidebar: $showSidebar,
                        messageText: $messageText,
                        selectedMessageSender: $selectedMessageSender,
                        selectedMessageSenderID: $selectedMessageSenderID,
                        imagePreviewURL: $imagePreviewURL,
                        windowCountPublic: $windowCountPublic,
                        windowCountPrivate: $windowCountPrivate,
                        isAtBottomPrivate: $isAtBottomPrivate,
                        isTextFieldFocused: isTextFieldFocused,
                        voiceRecordingVM: voiceRecordingVM,
                        autocompleteDebounceTimer: $autocompleteDebounceTimer,
                        onSendMessage: onSendMessage
                    )
                    #endif
                } else {
                    ContentPeopleListView(
                        showSidebar: $showSidebar,
                        showVerifySheet: $showVerifySheet
                    )
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { appChromeModel.showingFingerprintFor != nil && (showSidebar || privateConversationModel.selectedPeerID != nil) },
                set: { isPresented in
                    if !isPresented {
                        appChromeModel.clearFingerprint()
                    }
                }
            )) {
                if let peerID = appChromeModel.showingFingerprintFor {
                    FingerprintView(peerID: peerID)
                        .environmentObject(verificationModel)
                        .foregroundColor(palette.primary)
                }
            }
            // This sheet covers the root header where the connectivity
            // banner lives; a person sitting in the people list or a DM
            // would otherwise get no persistent signal that the radio is
            // off or tor is stalled. Mirror it here.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let issue = ConnectivityIssue.resolve(
                    bluetoothState: appChromeModel.bluetoothState,
                    torBlocked: appChromeModel.torBlocked
                ) {
                    ConnectivityStatusBanner(issue: issue)
                }
            }
        }
        .confirmationDialog(
            String(
                localized: "content.private_media.legacy_warning.title",
                defaultValue: "Send without end-to-end encryption?",
                comment: "Title warning before sending private media to an older client in a clear signed envelope"
            ),
            isPresented: Binding(
                get: { legacyConsentRequest != nil },
                set: { isPresented in
                    if !isPresented, let requestID = legacyConsentRequest?.id {
                        conversationUIModel.resolveLegacyPrivateMediaConsent(
                            requestID: requestID,
                            approved: false
                        )
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                String(
                    localized: "content.private_media.legacy_warning.send",
                    defaultValue: "send visible file",
                    comment: "Destructive confirmation action for one legacy clear private-media send"
                ),
                role: .destructive
            ) {
                if let requestID = legacyConsentRequest?.id {
                    conversationUIModel.resolveLegacyPrivateMediaConsent(
                        requestID: requestID,
                        approved: true
                    )
                }
            }
            Button("common.cancel", role: .cancel) {
                if let requestID = legacyConsentRequest?.id {
                    conversationUIModel.resolveLegacyPrivateMediaConsent(
                        requestID: requestID,
                        approved: false
                    )
                }
            }
        } message: {
            if let request = legacyConsentRequest {
                Text(
                    String(
                        format: String(
                            localized: "content.private_media.legacy_warning.message",
                            defaultValue: "%@'s client does not advertise encrypted private media. This file will be signed but not end-to-end encrypted, so mesh relays can see it. Send this file anyway?",
                            comment: "Warning explaining the confidentiality loss for one legacy private-media send; parameter is the peer name"
                        ),
                        locale: .current,
                        request.peerName
                    )
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { showImagePicker && (showSidebar || privateConversationModel.selectedPeerID != nil) },
            set: { newValue in
                if !newValue {
                    showImagePicker = false
                }
            }
        )) {
            ImagePickerView(sourceType: imagePickerSourceType) { image in
                showImagePicker = false
                conversationUIModel.processSelectedImage(image)
            }
            .ignoresSafeArea()
        }
        #endif
        .alert(Text(String(localized: "voice.error.title", defaultValue: "recording error", comment: "Title of the voice recording error alert")), isPresented: voiceAlertBinding, actions: {
            Button("common.ok", role: .cancel) {}
            if voiceRecordingVM.state == .permissionDenied {
                Button("location_channels.action.open_settings") {
                    SystemSettings.microphone.open()
                }
            }
        }, message: {
            Text(voiceRecordingVM.state.alertMessage)
        })
        .alert(
            "content.alert.bluetooth_required.title",
            isPresented: bluetoothAlertBinding
        ) {
            Button("content.alert.bluetooth_required.settings") {
                // Powered-off needs the radio controls, not the privacy pane.
                (appChromeModel.bluetoothState == .poweredOff
                    ? SystemSettings.bluetoothPower
                    : SystemSettings.bluetooth).open()
            }
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(appChromeModel.bluetoothAlertMessage)
        }
    }
}

private struct ContentPeopleListView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @Environment(\.dismiss) private var dismiss

    @Binding var showSidebar: Bool
    @Binding var showVerifySheet: Bool

    /// Bumped each time the list appears on a location channel, right after
    /// the roster rebuild, so the geohash section drops its remembered order.
    @State private var geohashOrderGeneration = 0

    var body: some View {
        List {
            switch locationChannelsModel.selectedChannel {
            case .location(let channel):
                GeohashPeopleList(
                    geohash: channel.geohash,
                    orderGeneration: geohashOrderGeneration,
                    onTapPerson: {
                        showSidebar = true
                    }
                )
                // Direct conversations survive channel switches; the geoDM
                // someone opened from another cell must stay reachable here
                // too.
                RecentChatList(
                    chats: peerListModel.recentChatRows,
                    onTapChat: openConversation
                )
            case .mesh:
                MeshPeerList(
                    onTapPeer: openConversation,
                    onToggleFavorite: { peerID in
                        peerListModel.toggleFavorite(peerID: peerID)
                    },
                    onShowFingerprint: { peerID in
                        appChromeModel.showFingerprint(for: peerID)
                    },
                    onToggleBlock: { peer in
                        if peer.isBlocked {
                            conversationUIModel.unblock(peerID: peer.peerID, displayName: peer.displayName)
                        } else {
                            conversationUIModel.block(peerID: peer.peerID, displayName: peer.displayName)
                        }
                    }
                )
                // People in this area but beyond radio range, and private
                // groups: one sheet for the whole room.
                BridgePeopleList()
                GroupChatList(
                    groups: peerListModel.groupRows,
                    onTapGroup: openConversation
                )
                // Conversations with people no roster above lists anymore —
                // without this, a read DM from an offline non-favorite had
                // no row anywhere in the UI.
                RecentChatList(
                    chats: peerListModel.recentChatRows,
                    onTapChat: openConversation
                )
            }
        }
        .peopleListStyle()
        // Inside the id so it runs again for a new channel.
        .onAppear(perform: refreshGeohashRoster)
        // Keyed by channel only. Rows are keyed by person, so roster
        // updates diff in place; a key derived from the rows rebuilds the
        // whole list on every heartbeat and resets its stable ordering.
        .id(ConversationID(channelID: locationChannelsModel.selectedChannel))
        .navigationTitle(Text(verbatim: peopleSheetTitle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            SheetCloseToolbarItem(action: close)
            if case .mesh = locationChannelsModel.selectedChannel {
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
        .sheet(isPresented: $showVerifySheet) {
            VerificationSheetView(isPresented: $showVerifySheet)
                .environmentObject(verificationModel)
        }
    }
}

private extension ContentPeopleListView {
    enum Strings {
        static let verification = String(localized: "content.accessibility.verification", comment: "Accessibility label for the verification QR button")
        static let verificationHelp = String(localized: "content.help.verification", comment: "Help text for verification button")
    }

    /// The catalog stores the old all-caps header ("PEOPLE"); title case
    /// suits a navigation title and keeps every translation.
    var peopleSheetTitle: String {
        String(localized: "content.header.people", comment: "Title for the people list sheet").localizedCapitalized
    }

    func openConversation(with peerID: PeerID) {
        peerListModel.startConversation(with: peerID)
        showSidebar = true
    }

    func close() {
        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
            dismiss()
            showSidebar = false
            showVerifySheet = false
            privateConversationModel.endConversation()
        }
    }

    /// The geohash roster republishes only when membership or names change,
    /// so its recency order can be stale. Rebuild it once as the list
    /// appears, then drop the remembered order so the sheet opens with the
    /// most recently active people first.
    func refreshGeohashRoster() {
        guard case .location = locationChannelsModel.selectedChannel else { return }
        peerListModel.refreshNow()
        geohashOrderGeneration += 1
    }
}

private struct ContentPrivateChatSheetView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel

    @Binding var showSidebar: Bool
    @Binding var messageText: String
    @Binding var selectedMessageSender: String?
    @Binding var selectedMessageSenderID: PeerID?
    @Binding var imagePreviewURL: URL?
    @Binding var windowCountPublic: Int
    @Binding var windowCountPrivate: [PeerID: Int]
    @Binding var isAtBottomPrivate: Bool
    var isTextFieldFocused: FocusState<Bool>.Binding
    @ObservedObject var voiceRecordingVM: VoiceRecordingViewModel
    @Binding var autocompleteDebounceTimer: Timer?
    @ThemedPalette private var palette

    let onSendMessage: () -> Void

    #if os(iOS)
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSourceType: UIImagePickerController.SourceType
    #endif

    var body: some View {
        // The people sheet's NavigationStack hosts this view, so the title
        // and the buttons go into that stack's bar: no second stack here.
        VStack(spacing: 0) {
            MessageListView(
                privatePeer: privateConversationModel.selectedPeerID,
                isAtBottom: $isAtBottomPrivate,
                messageText: $messageText,
                selectedMessageSender: $selectedMessageSender,
                selectedMessageSenderID: $selectedMessageSenderID,
                imagePreviewURL: $imagePreviewURL,
                windowCountPublic: $windowCountPublic,
                windowCountPrivate: $windowCountPrivate,
                showSidebar: $showSidebar,
                isTextFieldFocused: isTextFieldFocused
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Swipe-right-to-leave lives on the message list only. On the
            // whole sheet it preempted the composer's press-and-hold mic
            // gesture (a high-priority ancestor drag cancels child gestures
            // within milliseconds — same starvation as the image-reveal bug).
            .highPriorityGesture(swipeToLeaveGesture)

            privacyCaption

            #if os(iOS)
            ContentComposerView(
                messageText: $messageText,
                isTextFieldFocused: isTextFieldFocused,
                voiceRecordingVM: voiceRecordingVM,
                autocompleteDebounceTimer: $autocompleteDebounceTimer,
                onSendMessage: onSendMessage,
                showImagePicker: $showImagePicker,
                imagePickerSourceType: $imagePickerSourceType
            )
            #else
            ContentComposerView(
                messageText: $messageText,
                isTextFieldFocused: isTextFieldFocused,
                voiceRecordingVM: voiceRecordingVM,
                autocompleteDebounceTimer: $autocompleteDebounceTimer,
                onSendMessage: onSendMessage
            )
            #endif
        }
        .foregroundColor(palette.primary)
        .navigationTitle(Text(verbatim: headerState?.displayName ?? ""))
        .privateChatSubtitle(statusText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
    }

    private var headerState: PrivateConversationHeaderState? {
        privateConversationModel.selectedHeaderState
    }

    /// iOS before 26 has no navigation subtitle, so there the title slot
    /// holds the name with the status line under it.
    private var needsTitleFallback: Bool {
        #if os(iOS)
        if #available(iOS 26.0, *) { return false }
        return true
        #else
        return false
        #endif
    }

    // MARK: - Toolbar

    // iOS: back on the leading edge; info, favorite and close on the
    // trailing edge, as in the old header. A macOS sheet shows no leading,
    // trailing or principal items: automatic items go to the leading edge
    // of its bottom button bar and close to the trailing edge.
    #if os(iOS)
    private var leadingPlacement: ToolbarItemPlacement { .navigationBarLeading }
    private var actionPlacement: ToolbarItemPlacement { .navigationBarTrailing }
    private var closePlacement: ToolbarItemPlacement { .navigationBarTrailing }
    #else
    private var leadingPlacement: ToolbarItemPlacement { .automatic }
    private var actionPlacement: ToolbarItemPlacement { .automatic }
    private var closePlacement: ToolbarItemPlacement { .cancellationAction }
    #endif

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: leadingPlacement) {
            backButton
        }
        if needsTitleFallback, let headerState {
            ToolbarItem(placement: .principal) {
                PrivateChatTitleView(
                    title: headerState.displayName,
                    subtitle: statusText
                )
            }
        }
        if let headerState {
            // A group has no single fingerprint to show.
            if !headerState.isGroupConversation {
                ToolbarItem(placement: actionPlacement) {
                    fingerprintButton(headerState)
                }
            }
            if headerState.supportsFavoriteToggle {
                ToolbarItem(placement: actionPlacement) {
                    favoriteButton(headerState)
                }
            }
        }
        SheetCloseToolbarItem(placement: closePlacement) {
            withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                privateConversationModel.endConversation()
                showSidebar = true
            }
        }
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                privateConversationModel.endConversation()
            }
        } label: {
            Label(Strings.backToMainChat, systemImage: "chevron.left")
                .labelStyle(.iconOnly)
        }
        #if os(macOS)
        .help(Strings.backToMainChat)
        #endif
    }

    private func fingerprintButton(_ headerState: PrivateConversationHeaderState) -> some View {
        let status = headerState.encryptionStatus
        return Button {
            appChromeModel.showFingerprint(for: headerState.headerPeerID)
        } label: {
            Label {
                Text(verbatim: Strings.verifyEncryption)
            } icon: {
                // The lock tells the session state at a glance; a peer with
                // no handshake yet gets a neutral glyph, as the old header
                // showed no lock for it.
                Image(systemName: status?.icon ?? "info.circle")
                    .foregroundStyle(Self.isSecured(status) ? Color.primary : Color.red)
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityValue(status.map(Strings.encryptionStatus) ?? "")
        .accessibilityHint(Strings.viewFingerprintHint)
        #if os(macOS)
        .help(Strings.verifyEncryption)
        #endif
    }

    private func favoriteButton(_ headerState: PrivateConversationHeaderState) -> some View {
        let label = headerState.isFavorite ? Strings.removeFavorite : Strings.addFavorite
        return Button {
            privateConversationModel.toggleFavoriteForSelectedConversation()
        } label: {
            Label {
                Text(verbatim: label)
            } icon: {
                Image(systemName: headerState.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(headerState.isFavorite ? Color.yellow : Color.primary)
            }
            .labelStyle(.iconOnly)
        }
        #if os(macOS)
        .help(label)
        #endif
    }

    /// No icon (no handshake yet) counts as secured, so the neutral glyph
    /// is not painted red.
    private static func isSecured(_ status: EncryptionStatus?) -> Bool {
        switch status {
        case nil, .some(.noHandshake), .some(.noiseSecured), .some(.noiseVerified):
            return true
        case .some(.none), .some(.noiseHandshaking):
            return false
        }
    }

    /// The status under the name: how the peer is reachable and, once a
    /// handshake has started, the encryption state. The same facts the old
    /// header showed as icons.
    private var statusText: String {
        guard let headerState else { return "" }
        if headerState.isGroupConversation {
            return Strings.groupChat
        }
        let availability: String
        switch headerState.availability {
        case .bluetoothConnected: availability = Strings.connectedMesh
        case .meshReachable: availability = Strings.reachableMesh
        case .nostrAvailable: availability = Strings.availableNostr
        case .offline: availability = Strings.offline
        }
        guard let status = headerState.encryptionStatus, status.icon != nil else {
            return availability
        }
        return "\(availability) · \(status.description)"
    }

    private var swipeToLeaveGesture: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard horizontal > 80, vertical < 60 else { return }
                withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                    showSidebar = true
                    privateConversationModel.endConversation()
                }
            }
    }

    /// Persistent one-line reminder that this composer feeds a private
    /// conversation — the DM sheet otherwise renders identically to the
    /// public timeline. Claims end-to-end encryption only once the session
    /// is actually secured.
    private var privacyCaption: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.bitchatSystem(size: 9))
                // Optical centering: lock.fill's ink is bottom-heavy, so
                // geometric centering reads low next to the caption text.
                .offset(y: -1)
            Text(verbatim: privacyCaptionText)
                .bitchatFont(size: 11, weight: .medium)
        }
        .foregroundColor(Color.orange)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        // The orange text is signature enough; a tinted band here reads as a
        // stray strip against the untinted composer chrome below it, so the
        // caption sits on the same surface as the rest of the bottom chrome.
        .accessibilityElement(children: .combine)
    }

    private var privacyCaptionText: String {
        // Group chats are ChaCha20-Poly1305 sealed to the roster's shared key.
        if privateConversationModel.selectedPeerID?.isGroup == true {
            return String(localized: "content.private.caption_group", comment: "Caption above the group chat composer noting messages are encrypted to group members")
        }
        // Geohash DMs use BitChat's private-envelope encryption over Nostr —
        // always end-to-end encrypted,
        // even though they carry no Noise session status. Mesh DMs earn the
        // "encrypted" claim only once the Noise handshake has secured — or
        // when the peer is reachable only over Nostr, where delivery is
        // gift-wrapped end-to-end without a Noise session.
        let isGeoDM = privateConversationModel.selectedPeerID?.isGeoDM == true
        let noiseSecured: Bool = {
            switch privateConversationModel.selectedHeaderState?.encryptionStatus {
            case .noiseSecured, .noiseVerified: return true
            default: return false
            }
        }()
        let nostrTransport = privateConversationModel.selectedHeaderState?.availability == .nostrAvailable
        if isGeoDM || noiseSecured || nostrTransport {
            return String(localized: "content.private.caption_encrypted", comment: "Caption above the private chat composer once the session is end-to-end encrypted")
        }
        return String(localized: "content.private.caption", comment: "Caption above the private chat composer before encryption is established")
    }
}

private extension ContentPrivateChatSheetView {
    enum Strings {
        static let backToMainChat = String(localized: "content.accessibility.back_to_main_chat", comment: "Accessibility label for returning to main chat")
        static let verifyEncryption = String(localized: "content.accessibility.verification", comment: "Accessibility label for the verification QR button")
        static let viewFingerprintHint = String(localized: "content.accessibility.view_fingerprint_hint", comment: "Accessibility hint for viewing encryption fingerprint")
        static let addFavorite = String(localized: "content.accessibility.add_favorite", comment: "Accessibility label to add a favorite")
        static let removeFavorite = String(localized: "content.accessibility.remove_favorite", comment: "Accessibility label to remove a favorite")
        static let groupChat = String(localized: "content.accessibility.group_chat", comment: "Accessibility label for the group chat indicator")
        static let connectedMesh = String(localized: "content.accessibility.connected_mesh", comment: "Accessibility label for mesh-connected peer indicator")
        static let reachableMesh = String(localized: "content.accessibility.reachable_mesh", comment: "Accessibility label for mesh-reachable peer indicator")
        static let availableNostr = String(localized: "content.accessibility.available_nostr", comment: "Accessibility label for Nostr-available peer indicator")
        static let offline = String(localized: "mesh_peers.state.offline", comment: "State label for a peer that is not currently reachable")

        static func encryptionStatus(_ status: EncryptionStatus) -> String {
            String(
                format: String(localized: "content.accessibility.encryption_status", comment: "Accessibility label announcing encryption status"),
                locale: .current,
                status.accessibilityDescription
            )
        }

        static func privateChatHeader(_ name: String) -> String {
            String(
                format: String(localized: "content.accessibility.private_chat_header", comment: "Accessibility label describing the private chat header"),
                locale: .current,
                name
            )
        }
    }
}

/// The title for iOS before 26, which has no navigation subtitle: the name
/// over a status line, sized like the system's inline title.
private struct PrivateChatTitleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: title)
                .font(.headline)
                // Middle truncation keeps the identity suffix of a long
                // nickname visible.
                .lineLimit(1)
                .truncationMode(.middle)
            if !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ContentPrivateChatSheetView.Strings.privateChatHeader(title))
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    /// The status line under the navigation title, where the system has
    /// one: macOS, and iOS from 26.
    @ViewBuilder
    func privateChatSubtitle(_ subtitle: String) -> some View {
        #if os(iOS)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            navigationSubtitle(Text(verbatim: subtitle))
        } else {
            self
        }
        #else
        self
        #endif
        #else
        navigationSubtitle(Text(verbatim: subtitle))
        #endif
    }
}
