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
/// person's name and status, the orange privacy caption and the composer
/// floating over them, and the fingerprint and favorite buttons in the
/// toolbar. The split view supplies the way back.
struct PrivateChatDetailView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
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
            showSidebar: .constant(false),
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
        .background(ThemedRootBackground())
        .foregroundColor(palette.primary)
        .navigationTitle(Text(verbatim: headerState?.displayName ?? ""))
        .privateChatSubtitle(statusText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if needsTitleFallback, let headerState {
            ToolbarItem(placement: .principal) {
                PrivateChatTitleView(
                    title: headerState.displayName,
                    subtitle: statusText
                )
            }
        }
        if let headerState {
            ToolbarItemGroup(placement: .primaryAction) {
                // A group has no single fingerprint to show.
                if !headerState.isGroupConversation {
                    fingerprintButton(headerState)
                }
                if headerState.supportsFavoriteToggle {
                    favoriteButton(headerState)
                }
            }
        }
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
                // no handshake yet gets a neutral glyph.
                Image(systemName: status?.icon ?? "info.circle")
                    .foregroundStyle(Self.isSecured(status) ? Color.primary : Color.red)
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityValue(status.map(Strings.encryptionStatus) ?? "")
        .accessibilityHint(Strings.viewFingerprintHint)
        .help(Strings.verifyEncryption)
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
        .help(label)
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
        .accessibilityLabel(PrivateChatDetailView.Strings.privateChatHeader(title))
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
