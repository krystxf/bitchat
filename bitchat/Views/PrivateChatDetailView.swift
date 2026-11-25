//
// PrivateChatDetailView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A direct conversation (a DM or a private group) as the detail of the
/// main window's split view: the messages under a native title bar with the
/// person's name and status, and the orange privacy caption and the
/// composer floating over them. The title (on macOS, the details button)
/// opens the conversation's info page, which holds everything else
/// (favorite, verify, background, group members). The split view supplies
/// the way back.
struct PrivateChatDetailView: View {
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel

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
    @State private var chatBackgroundOption: ChatBackgroundOption = .default
    /// The conversation info page, opened from the title.
    @State private var showsInfo = false
    @ThemedPalette private var palette

    let onSendMessage: () -> Void

    #if os(iOS)
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSourceType: UIImagePickerController.SourceType
    #endif

    var body: some View {
        MessageListView(
            privatePeer: privateConversationModel.selectedPeerID,
            isAtBottom: $isAtBottomPrivate,
            messageText: $messageText,
            selectedMessageSender: $selectedMessageSender,
            selectedMessageSenderID: $selectedMessageSenderID,
            imagePreviewURL: $imagePreviewURL,
            windowCountPublic: $windowCountPublic,
            windowCountPrivate: $windowCountPrivate,
            isTextFieldFocused: isTextFieldFocused
        )
        .floatingBar(edge: .top) {
            ContentStatusBanners()
        }
        .floatingBar(edge: .bottom) {
            VStack(spacing: 0) {
                privacyCaption
                composer
            }
        }
        // macOS: drop an image anywhere on the conversation to send it.
        .imageDropTarget(isEnabled: conversationUIModel.canSendMediaInCurrentContext) { url in
            conversationUIModel.processSelectedImage(from: url)
        }
        .background {
            ChatConversationBackground(option: chatBackgroundOption, conversationKey: chatBackgroundConversationKey)
                .animation(.easeInOut(duration: 0.2), value: chatBackgroundOption)
        }
        .foregroundColor(palette.primary)
        // The title button below shows the name; the title still names the
        // window and the back button of the info page.
        .navigationTitle(Text(verbatim: headerState?.displayName ?? ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .conversationTitleBar(subtitle: statusText)
        .conversationInfo(isPresented: $showsInfo) {
            if headerState?.isGroupConversation == true {
                GroupInfoPage(
                    background: $chatBackgroundOption,
                    backgroundKey: chatBackgroundConversationKey
                )
            } else {
                PersonInfoPage(
                    subtitle: statusText,
                    background: $chatBackgroundOption,
                    backgroundKey: chatBackgroundConversationKey
                )
            }
        }
        .onAppear { loadChatBackground() }
        .onChange(of: privateConversationModel.selectedPeerID) { _ in
            loadChatBackground()
            // The page belongs to the conversation it was opened from.
            showsInfo = false
        }
    }

    @ViewBuilder
    private var composer: some View {
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

    private var headerState: PrivateConversationHeaderState? {
        privateConversationModel.selectedHeaderState
    }

    // MARK: - Toolbar

    /// Only the title: a button that opens the conversation info page.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let headerState {
            ConversationTitleToolbarItem(
                title: Text(verbatim: headerState.displayName),
                subtitle: statusText,
                accessibilityLabel: headerState.isGroupConversation
                    ? nil
                    : Strings.privateChatHeader(headerState.displayName)
            ) {
                showsInfo.toggle()
            }
        }
    }

    private var chatBackgroundConversationKey: ComposerDraftStore.Key {
        guard let peerID = privateConversationModel.selectedPeerID else { return .mesh }
        if let fingerprint = conversationUIModel.getFingerprint(for: peerID), !fingerprint.isEmpty {
            return .privateChat(stableID: fingerprint)
        }
        return .privateChat(stableID: peerID.id)
    }

    private func loadChatBackground() {
        chatBackgroundOption = ChatBackgroundStore.shared.option(for: chatBackgroundConversationKey)
    }

    /// The status under the name: how the peer is reachable and, once a
    /// handshake has started, the encryption state.
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

    /// Persistent one-line reminder that this composer feeds a private
    /// conversation, which otherwise renders like the public timeline.
    /// Claims end-to-end encryption only once the session is secured.
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
        // The orange text is signature enough; the caption sits on the same
        // surface as the rest of the bottom chrome.
        .accessibilityElement(children: .combine)
    }

    private var privacyCaptionText: String {
        // Group chats are ChaCha20-Poly1305 sealed to the roster's shared key.
        if privateConversationModel.selectedPeerID?.isGroup == true {
            return String(localized: "content.private.caption_group", comment: "Caption above the group chat composer noting messages are encrypted to group members")
        }
        // Geohash DMs use BitChat's private-envelope encryption over Nostr:
        // always end-to-end encrypted, even though they carry no Noise
        // session status. Mesh DMs earn the "encrypted" claim only once the
        // Noise handshake has secured, or when the peer is reachable only
        // over Nostr, where delivery is gift-wrapped end-to-end.
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

private extension PrivateChatDetailView {
    enum Strings {
        static let groupChat = String(localized: "content.accessibility.group_chat", comment: "Accessibility label for the group chat indicator")
        static let connectedMesh = String(localized: "content.accessibility.connected_mesh", comment: "Accessibility label for mesh-connected peer indicator")
        static let reachableMesh = String(localized: "content.accessibility.reachable_mesh", comment: "Accessibility label for mesh-reachable peer indicator")
        static let availableNostr = String(localized: "content.accessibility.available_nostr", comment: "Accessibility label for Nostr-available peer indicator")
        static let offline = String(localized: "mesh_peers.state.offline", comment: "State label for a peer that is not currently reachable")

        static func privateChatHeader(_ name: String) -> String {
            String(
                format: String(localized: "content.accessibility.private_chat_header", comment: "Accessibility label describing the private chat header"),
                locale: .current,
                name
            )
        }
    }
}
