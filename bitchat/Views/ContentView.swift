//
// ContentView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import BitFoundation

struct ContentRootModalPresentationState {
    var isAppInfoPresented = false
    var isFingerprintPresented = false
    var isLocationChannelsSheetPresented = false
    var isNoticesSheetPresented = false
    var isImagePreviewPresented = false
    var isVerificationSheetPresented = false
    var legacyPrivateMediaConsentRequest: LegacyPrivateMediaConsentRequest? = nil
    var isVoiceAlertPresented = false
    var isScreenshotPrivacyAlertPresented = false
    var isMediaPickerPresented = false

    var hasPresentation: Bool {
        isAppInfoPresented
            || isFingerprintPresented
            || isLocationChannelsSheetPresented
            || isNoticesSheetPresented
            || isImagePreviewPresented
            || isVerificationSheetPresented
            || legacyPrivateMediaConsentRequest != nil
            || isVoiceAlertPresented
            || isScreenshotPrivacyAlertPresented
            || isMediaPickerPresented
    }
}

extension ContentRootModalPresentationState {
    @MainActor
    init(
        appChromeModel: AppChromeModel,
        isImagePreviewPresented: Bool = false,
        isVerificationSheetPresented: Bool = false,
        legacyPrivateMediaConsentRequest: LegacyPrivateMediaConsentRequest? = nil,
        isVoiceAlertPresented: Bool = false,
        isMediaPickerPresented: Bool = false
    ) {
        self.init(
            isAppInfoPresented: appChromeModel.isAppInfoPresented,
            isFingerprintPresented:
                appChromeModel.showingFingerprintFor != nil,
            isLocationChannelsSheetPresented:
                appChromeModel.isLocationChannelsSheetPresented,
            isNoticesSheetPresented:
                appChromeModel.isNoticesSheetPresented,
            isImagePreviewPresented: isImagePreviewPresented,
            isVerificationSheetPresented: isVerificationSheetPresented,
            legacyPrivateMediaConsentRequest: legacyPrivateMediaConsentRequest,
            isVoiceAlertPresented: isVoiceAlertPresented,
            isScreenshotPrivacyAlertPresented:
                appChromeModel.showScreenshotPrivacyWarning,
            isMediaPickerPresented: isMediaPickerPresented
        )
    }
}

/// On macOS 14+, disables the default system focus ring on TextFields.
/// On earlier macOS versions and on iOS this is a no-op.
struct FocusEffectDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct ContentView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var sharedContentImportModel: SharedContentImportModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var boardAlertsModel: BoardAlertsModel
    @EnvironmentObject private var publicChatModel: PublicChatModel
    @EnvironmentObject private var privateInboxModel: PrivateInboxModel

    @StateObject private var voiceRecordingVM = VoiceRecordingViewModel()
    @State private var messageText = ""
    /// Conversation the current `messageText` belongs to, so a channel switch
    /// can save under the previous key before loading the next draft.
    @State private var activeDraftKey: ComposerDraftStore.Key = .mesh
    @State private var chatBackgroundOption: ChatBackgroundOption = .default
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// The sidebar's selection. It mirrors the models, which stay the source
    /// of truth (`currentSidebarItem`); `nil` means the compact split view
    /// shows the sidebar list. Starts on #mesh until the view appears and
    /// reads the open conversation, so the compact split view never starts
    /// out on the list.
    @State private var sidebarSelection: SidebarItem? = .mesh
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Which column the collapsed (compact) split view shows. Starts in the
    /// chat, as Messages does with an open conversation.
    @State private var showsDetailWhenCompact = true
    @State private var selectedMessageSender: String?
    @State private var selectedMessageSenderID: PeerID?
    @State private var isAtBottomPublic = true
    @State private var isAtBottomPrivate = true
    @State private var autocompleteDebounceTimer: Timer?
    @State private var showVerifySheet = false
    @State private var imagePreviewURL: URL?
    #if os(iOS)
    @State private var showImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    #endif
    @State private var windowCountPublic: Int = 300
    @State private var windowCountPrivate: [PeerID: Int] = [:]
    @State private var boardPosts: [BoardPostPacket] = []
    @ObservedObject private var nearbyNotes = NearbyNotesCounter.shared

    @ThemedPalette private var palette

    private var selectedPrivatePeerID: PeerID? {
        privateConversationModel.selectedPeerID
    }

    private var sharedContentDestination: SharedContentDestination {
        SharedContentDestination.resolve(
            selectedPrivatePeerID: selectedPrivatePeerID,
            privateDisplayName: privateConversationModel.selectedHeaderState?.displayName,
            activeChannel: locationChannelsModel.selectedChannel
        )
    }

    private func rootModalPresentationState(
        includingVoiceAlert: Bool
    ) -> ContentRootModalPresentationState {
        #if os(iOS)
        let isMediaPickerPresented = showImagePicker
        #else
        // The macOS open panel is window-modal and needs no flag.
        let isMediaPickerPresented = false
        #endif

        return ContentRootModalPresentationState(
            appChromeModel: appChromeModel,
            isImagePreviewPresented: imagePreviewURL != nil,
            isVerificationSheetPresented: showVerifySheet,
            legacyPrivateMediaConsentRequest:
                conversationUIModel.legacyPrivateMediaConsentRequest,
            isVoiceAlertPresented: includingVoiceAlert && voiceRecordingVM.showAlert,
            isMediaPickerPresented: isMediaPickerPresented
        )
    }

    private var hasRootModalPresentation: Bool {
        rootModalPresentationState(includingVoiceAlert: true).hasPresentation
    }

    /// The voice alert cannot defer to itself: its own binding must keep
    /// reporting `true` while it is the presented modal.
    private var hasRootModalPresentationBesidesVoiceAlert: Bool {
        rootModalPresentationState(includingVoiceAlert: false).hasPresentation
    }

    private var rootBluetoothAlertBinding: Binding<Bool> {
        Binding(
            get: {
                scenePhase == .active
                    && appChromeModel.showBluetoothAlert
                    && !hasRootModalPresentation
            },
            set: { isPresented in
                guard !isPresented,
                      scenePhase == .active,
                      !hasRootModalPresentation else {
                    return
                }
                // SwiftUI can invoke this setter inside a view update (the
                // alert dismisses when a scenePhase change re-evaluates the
                // `get`); publishing synchronously there is undefined
                // behavior, so defer the write one hop.
                Task { @MainActor in
                    appChromeModel.showBluetoothAlert = false
                }
            }
        )
    }

    /// Voice recording errors defer to any other root modal: presenting the
    /// alert then would force-dismiss it. Mirrors the Bluetooth alert
    /// treatment above.
    private var rootVoiceAlertBinding: Binding<Bool> {
        Binding(
            get: {
                scenePhase == .active
                    && voiceRecordingVM.showAlert
                    && !hasRootModalPresentationBesidesVoiceAlert
            },
            set: { isPresented in
                guard !isPresented,
                      scenePhase == .active,
                      !hasRootModalPresentationBesidesVoiceAlert else {
                    return
                }
                // Same deferral as the Bluetooth alert above: the setter can
                // run inside a view update when the modal state changes.
                Task { @MainActor in
                    voiceRecordingVM.showAlert = false
                }
            }
        )
    }

    var body: some View {
        splitView
            .onReceive(BoardStore.shared.$postsSnapshot) { boardPosts = $0 }
            .onAppear { [conversationUIModel, voiceRecordingVM] in
                conversationUIModel.setCurrentColorScheme(colorScheme)
                voiceRecordingVM.sessionProvider = { [weak conversationUIModel] in
                    conversationUIModel?.makeVoiceCaptureSession() ?? VoiceNoteCaptureSession()
                }
                appChromeModel.setPanicPreparation { [weak voiceRecordingVM] in
                    voiceRecordingVM?.panicWipe()
                    // Drop in-memory composer text before ChatViewModel resets
                    // persisted drafts — otherwise the next inactive/background
                    // transition would write the pre-wipe draft back.
                    messageText = ""
                    activeDraftKey = .mesh
                }
                #if os(macOS)
                DispatchQueue.main.async {
                    isTextFieldFocused = true
                }
                #endif
                sharedContentImportModel.updateDestination(sharedContentDestination)
                activeDraftKey = ComposerDraftStore.Key.from(
                    peerID: selectedPrivatePeerID,
                    fingerprint: selectedPrivatePeerID.flatMap { conversationUIModel.getFingerprint(for: $0) },
                    channel: locationChannelsModel.selectedChannel
                )
                chatBackgroundOption = ChatBackgroundStore.shared.option(for: activeDraftKey)
                messageText = ComposerDraftStore.load(activeDraftKey)
                sidebarSelection = currentSidebarItem
            }
            .onChange(of: colorScheme) { newValue in
                conversationUIModel.setCurrentColorScheme(newValue)
            }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
        .onChange(of: selectedPrivatePeerID) { newValue in
            sharedContentImportModel.updateDestination(sharedContentDestination)
            switchComposerDraft(to: ComposerDraftStore.Key.from(
                peerID: newValue,
                fingerprint: newValue.flatMap { conversationUIModel.getFingerprint(for: $0) },
                channel: locationChannelsModel.selectedChannel
            ))
            if let newValue {
                // Opened from anywhere (a message's DM action, the unread
                // envelope, a notification): show it.
                showInSidebar(.conversation(newValue))
            } else if case .conversation = sidebarSelection {
                // Ended on its own (a block, a panic wipe): the channel takes
                // its place. A channel the user picked is already selected,
                // and leaving from the compact list keeps the list.
                sidebarSelection = SidebarItem(channel: locationChannelsModel.selectedChannel)
            }
        }
        .onChange(of: locationChannelsModel.selectedChannel) { newChannel in
            sharedContentImportModel.updateDestination(sharedContentDestination)
            // Private drafts are keyed by peer; only public channel switches
            // need a draft swap while no DM is open.
            if selectedPrivatePeerID == nil {
                switchComposerDraft(to: ComposerDraftStore.Key.from(
                    peerID: nil,
                    fingerprint: nil,
                    channel: newChannel
                ))
            } else {
                // The sidebar opens the location channels sheet over a DM
                // too; picking a channel there means going to it. Ending the
                // DM swaps the draft in its own change handler.
                privateConversationModel.endConversation()
            }
            // Switched from anywhere (the location channels sheet, the title
            // menu, a link): show it.
            showInSidebar(SidebarItem(channel: newChannel))
        }
        .onChange(of: sidebarSelection) { item in
            applySidebarSelection(item)
        }
        .onChange(of: showsDetailWhenCompact) { showsDetail in
            // The compact split view went back to the list.
            if !showsDetail, isCompact {
                sidebarSelection = nil
            }
        }
        .onChange(of: activeDraftKey) { key in
            chatBackgroundOption = ChatBackgroundStore.shared.option(for: key)
        }
        #if os(iOS)
        .onChange(of: horizontalSizeClass) { _ in
            // Regular width always shows a conversation, so it needs one
            // selected after the list was on screen in compact width.
            if !isCompact, sidebarSelection == nil {
                sidebarSelection = currentSidebarItem
            }
        }
        #endif
        .onChange(of: scenePhase) { phase in
            if phase == .background || phase == .inactive {
                // Always save, including empty — clearing the composer must
                // remove the in-memory draft so it does not resurrect on the
                // next switch back into this conversation.
                ComposerDraftStore.save(messageText, for: activeDraftKey)
            }
        }
        .sheet(isPresented: $appChromeModel.isAppInfoPresented) {
            AppInfoView(
                topologyProvider: { appChromeModel.meshTopologyDisplayModel() },
                onPanicWipe: { appChromeModel.panicClearAllData() },
                nickname: Binding(
                    get: { appChromeModel.nickname },
                    set: { appChromeModel.setNickname($0) }
                ),
                onNicknameCommit: { appChromeModel.validateAndSaveNickname() }
            )
            .environmentObject(locationChannelsModel)
        }
        .sheet(isPresented: Binding(
            get: { appChromeModel.showingFingerprintFor != nil },
            set: { _ in appChromeModel.clearFingerprint() }
        )) {
            if let peerID = appChromeModel.showingFingerprintFor {
                FingerprintSheet(peerID: peerID)
                    .environmentObject(verificationModel)
            }
        }
        .sheet(isPresented: $showVerifySheet) {
            VerificationSheetView(isPresented: $showVerifySheet)
                .environmentObject(verificationModel)
        }
        // Hosted at the root: the sidebar and the chat toolbar both open it.
        .sheet(isPresented: $appChromeModel.isLocationChannelsSheetPresented) {
            LocationChannelsSheet(isPresented: $appChromeModel.isLocationChannelsSheetPresented)
                .environmentObject(locationChannelsModel)
                .environmentObject(peerListModel)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSourceType) { image in
                showImagePicker = false
                conversationUIModel.processSelectedImage(image)
            }
            .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: Binding(
            get: { imagePreviewURL != nil },
            set: { presenting in
                if !presenting {
                    imagePreviewURL = nil
                }
            }
        )) {
            if let url = imagePreviewURL {
                ImagePreviewView(url: url)
            }
        }
        .modifier(LegacyPrivateMediaConsentDialog())
        .confirmationDialog(
            Text(
                String(localized: "app_info.settings.danger.panic_confirm_title", defaultValue: "wipe all data?", comment: "Title of the confirmation dialog before a panic wipe")
            ),
            isPresented: $appChromeModel.showPanicConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                appChromeModel.panicClearAllData()
            } label: {
                Text(
                    String(localized: "app_info.settings.danger.panic_confirm_action", defaultValue: "wipe everything", comment: "Destructive confirmation button that performs the panic wipe")
                )
            }
            Button("common.cancel", role: .cancel) {}
        }
        .alert(Text(String(localized: "voice.error.title", defaultValue: "recording error", comment: "Title of the voice recording error alert")), isPresented: rootVoiceAlertBinding, actions: {
            Button("common.ok", role: .cancel) {}
            if voiceRecordingVM.state == .permissionDenied {
                Button("location_channels.action.open_settings") {
                    SystemSettings.microphone.open()
                }
            }
        }, message: {
            Text(voiceRecordingVM.state.alertMessage)
        })
        .alert("content.alert.bluetooth_required.title", isPresented: rootBluetoothAlertBinding) {
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
        .alert("content.alert.screenshot.title", isPresented: $appChromeModel.showScreenshotPrivacyWarning) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("content.alert.screenshot.message")
        }
        .alert(
            String(localized: "share_import.review.title", comment: "Title for reviewing content received from the share extension"),
            isPresented: Binding(
                get: { sharedContentImportModel.offer != nil },
                set: { _ in }
            ),
            presenting: sharedContentImportModel.offer
        ) { _ in
            Button("common.cancel", role: .cancel) {
                sharedContentImportModel.cancel(destination: sharedContentDestination)
            }
            Button("share_import.review.use_in_composer") {
                guard let importedText = sharedContentImportModel.confirm(
                    destination: sharedContentDestination
                ) else { return }
                // Replacing is deliberate and called out in the prompt. It
                // avoids combining a stale draft from another conversation
                // with newly shared content.
                messageText = importedText
                isTextFieldFocused = true
            }
        } message: { offer in
            let format = String(
                localized: "share_import.review.message",
                comment: "Explains that shared content will replace the named destination's composer and will not be sent automatically"
            )
            Text(String(format: format, offer.destination.displayName) + "\n\n" + offer.payload.preview)
        }
        .onDisappear {
            autocompleteDebounceTimer?.invalidate()
            appChromeModel.setPanicPreparation(nil)
        }
    }

    // MARK: - Split view

    /// Channels and people in the sidebar, the selected conversation as the
    /// detail, as in Messages. iPhone collapses it to a stack that starts
    /// in the chat (iOS 17+; iOS 16 keeps the system default).
    @ViewBuilder
    private var splitView: some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            NavigationSplitView(
                columnVisibility: $columnVisibility,
                preferredCompactColumn: preferredCompactColumn
            ) {
                sidebar
            } detail: {
                detail
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detail
            }
        }
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        #endif
    }

    @available(iOS 17.0, macOS 14.0, *)
    private var preferredCompactColumn: Binding<NavigationSplitViewColumn> {
        Binding(
            get: { showsDetailWhenCompact ? .detail : .sidebar },
            set: { column in
                let showsDetail = column != .sidebar
                if showsDetail != showsDetailWhenCompact {
                    showsDetailWhenCompact = showsDetail
                }
            }
        )
    }

    private var sidebar: some View {
        ContentSidebarView(
            selection: $sidebarSelection,
            showVerifySheet: $showVerifySheet
        )
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        #endif
    }

    /// The open conversation, read from the models: a DM or private group
    /// when one is open, the public channel otherwise.
    @ViewBuilder
    private var detail: some View {
        Group {
            if selectedPrivatePeerID != nil {
                privateChat
            } else {
                publicChat
            }
        }
        // The chats' text color. Not on the whole split view: the sidebar
        // keeps the system's, which follows the selection highlight.
        .foregroundColor(palette.primary)
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 380, ideal: 640)
        #endif
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// The sidebar item for what the models have open.
    private var currentSidebarItem: SidebarItem {
        if let peerID = selectedPrivatePeerID {
            return .conversation(peerID)
        }
        return SidebarItem(channel: locationChannelsModel.selectedChannel)
    }

    /// Selects `item` for a change the models made, and brings the chat on
    /// screen in the compact split view.
    private func showInSidebar(_ item: SidebarItem) {
        if sidebarSelection != item {
            sidebarSelection = item
        }
        if isCompact, !showsDetailWhenCompact {
            showsDetailWhenCompact = true
        }
    }

    /// Opens what the user selected in the sidebar. Every path back from the
    /// models goes through `showInSidebar`, so applying a selection the
    /// models already have does nothing.
    private func applySidebarSelection(_ item: SidebarItem?) {
        guard let item else {
            if isCompact {
                // Back to the list: leave the private conversation.
                if selectedPrivatePeerID != nil {
                    privateConversationModel.endConversation()
                }
            } else {
                // Regular width always shows a conversation: keep it
                // selected (a macOS Command-click can deselect).
                sidebarSelection = currentSidebarItem
            }
            return
        }

        if isCompact, !showsDetailWhenCompact {
            showsDetailWhenCompact = true
        }

        switch item {
        case .mesh:
            leavePrivateConversation()
            if locationChannelsModel.selectedChannel != .mesh {
                locationChannelsModel.select(.mesh)
            }
        case .location(let geohash):
            leavePrivateConversation()
            locationChannelsModel.selectLocationChannel(geohash: geohash)
        case .conversation(let peerID):
            guard selectedPrivatePeerID != peerID else { return }
            if let pubkeyHex = peerListModel.geohashPubkeyHex(forConversation: peerID) {
                privateConversationModel.startGeohashConversation(withPubkeyHex: pubkeyHex)
            } else {
                privateConversationModel.startConversation(with: peerID)
            }
            // A blocked person's chat does not open: select what is open.
            let current = currentSidebarItem
            if sidebarSelection != current {
                sidebarSelection = current
            }
        }
    }

    private func leavePrivateConversation() {
        guard selectedPrivatePeerID != nil else { return }
        privateConversationModel.endConversation()
    }

    /// Reveals the people: the sidebar in the compact split view, or the
    /// sidebar column shown or hidden in regular width.
    private func togglePeople() {
        withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
            if isCompact {
                showsDetailWhenCompact = false
                sidebarSelection = nil
            } else {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
    }

    // MARK: - Detail

    /// Full-bleed message list under the native title bar, with the status
    /// banners and the composer floating over it (safe-area bars), so the
    /// translucency gains usable space instead of losing it.
    private var publicChat: some View {
        publicMessageList
            .floatingBar(edge: .top) {
                VStack(spacing: 0) {
                    ContentStatusBanners()
                    PinnedNoticesBar(posts: boardPosts, geoScope: activeNoticesGeoScope, nearbyNoteCount: nearbyNotes.noteCount) {
                        var scopes: Set<String> = [""]
                        if let scope = activeNoticesGeoScope { scopes.insert(scope) }
                        boardAlertsModel.markSeen(forScopes: scopes)
                        appChromeModel.presentNotices()
                    }
                }
            }
            .floatingBar(edge: .bottom) {
                composerView
            }
            // macOS: drop an image anywhere on the chat to send it.
            .imageDropTarget(isEnabled: conversationUIModel.canSendMediaInCurrentContext) { url in
                conversationUIModel.processSelectedImage(from: url)
            }
            .background {
                ChatConversationBackground(option: chatBackgroundOption)
                    .animation(.easeInOut(duration: 0.2), value: chatBackgroundOption)
            }
            .modifier(ContentHeaderToolbar(
                onShowPeople: togglePeople,
                backgroundOption: $chatBackgroundOption
            ))
    }

    private var activeNoticesGeoScope: String? {
        if case .location(let channel) = locationChannelsModel.selectedChannel { return channel.geohash }
        return locationChannelsModel.currentBuildingGeohash
    }

    private var publicMessageList: some View {
        MessageListView(
            privatePeer: nil,
            isAtBottom: $isAtBottomPublic,
            messageText: $messageText,
            selectedMessageSender: $selectedMessageSender,
            selectedMessageSenderID: $selectedMessageSenderID,
            imagePreviewURL: $imagePreviewURL,
            windowCountPublic: $windowCountPublic,
            windowCountPrivate: $windowCountPrivate,
            isTextFieldFocused: $isTextFieldFocused
        )
    }

    @ViewBuilder
    private var privateChat: some View {
        #if os(iOS)
        PrivateChatDetailView(
            messageText: $messageText,
            selectedMessageSender: $selectedMessageSender,
            selectedMessageSenderID: $selectedMessageSenderID,
            imagePreviewURL: $imagePreviewURL,
            windowCountPublic: $windowCountPublic,
            windowCountPrivate: $windowCountPrivate,
            isAtBottomPrivate: $isAtBottomPrivate,
            isTextFieldFocused: $isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: sendMessage,
            showImagePicker: $showImagePicker,
            imagePickerSourceType: $imagePickerSourceType
        )
        #else
        PrivateChatDetailView(
            messageText: $messageText,
            selectedMessageSender: $selectedMessageSender,
            selectedMessageSenderID: $selectedMessageSenderID,
            imagePreviewURL: $imagePreviewURL,
            windowCountPublic: $windowCountPublic,
            windowCountPrivate: $windowCountPrivate,
            isAtBottomPrivate: $isAtBottomPrivate,
            isTextFieldFocused: $isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: sendMessage
        )
        #endif
    }

    private var composerView: some View {
        #if os(iOS)
        ContentComposerView(
            messageText: $messageText,
            isTextFieldFocused: $isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: sendMessage,
            showImagePicker: $showImagePicker,
            imagePickerSourceType: $imagePickerSourceType
        )
        #else
        ContentComposerView(
            messageText: $messageText,
            isTextFieldFocused: $isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: sendMessage
        )
        #endif
    }

    private func sendMessage() {
        guard let trimmed = messageText.trimmedOrNilIfEmpty else { return }

        messageText = ""
        ComposerDraftStore.save("", for: activeDraftKey)

        DispatchQueue.main.async {
            self.conversationUIModel.sendMessage(trimmed)
        }
    }

    private func switchComposerDraft(to newKey: ComposerDraftStore.Key) {
        guard newKey != activeDraftKey else { return }
        ComposerDraftStore.save(messageText, for: activeDraftKey)
        activeDraftKey = newKey
        messageText = ComposerDraftStore.load(newKey)
    }
}

/// Asks before sending private media to an older client in a clear signed
/// envelope. Hosted at the root, so a pending request is answered even
/// when the user leaves the conversation it came from.
private struct LegacyPrivateMediaConsentDialog: ViewModifier {
    @EnvironmentObject private var conversationUIModel: ConversationUIModel

    func body(content: Content) -> some View {
        let request = conversationUIModel.legacyPrivateMediaConsentRequest
        content.confirmationDialog(
            String(
                localized: "content.private_media.legacy_warning.title",
                defaultValue: "Send without end-to-end encryption?",
                comment: "Title warning before sending private media to an older client in a clear signed envelope"
            ),
            isPresented: Binding(
                get: { request != nil },
                set: { isPresented in
                    if !isPresented, let requestID = request?.id {
                        resolve(requestID, approved: false)
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
                if let requestID = request?.id {
                    resolve(requestID, approved: true)
                }
            }
            Button("common.cancel", role: .cancel) {
                if let requestID = request?.id {
                    resolve(requestID, approved: false)
                }
            }
        } message: {
            if let request {
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
    }

    private func resolve(_ requestID: LegacyPrivateMediaConsentRequest.ID, approved: Bool) {
        conversationUIModel.resolveLegacyPrivateMediaConsent(requestID: requestID, approved: approved)
    }
}

extension View {
    /// Floating chrome over the message list. On OS 26+ a safe-area bar, so
    /// the list gets the system's scroll edge effect under the floating glass
    /// controls; a plain safe-area inset below.
    @ViewBuilder
    func floatingBar<Bar: View>(edge: VerticalEdge, @ViewBuilder content: () -> Bar) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: content)
        }
        #else
        safeAreaInset(edge: edge, spacing: 0, content: content)
        #endif
    }
}
