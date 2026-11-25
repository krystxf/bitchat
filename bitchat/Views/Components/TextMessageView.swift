//
// TextMessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import BitFoundation

struct TextMessageView: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @ThemedPalette private var palette
    @EnvironmentObject private var conversationUIModel: ConversationUIModel

    let message: BitchatMessage
    /// Value snapshot of the message's mutable delivery status, captured at
    /// construction. `BitchatMessage` is a reference type mutated in place by
    /// `ConversationStore`, and SwiftUI compares reference-typed view fields
    /// by identity — so a status-only change (e.g. delivered → read) on the
    /// SAME instance would otherwise compare "unchanged" and this row's body
    /// would be skipped even though the parent list re-rendered. Snapshotting
    /// the enum makes the change visible to SwiftUI's structural diff.
    private let deliveryStatus: DeliveryStatus
    /// Whether I wrote the message, which puts its bubble on the right. Nil
    /// asks the model; the list passes the answer it already has.
    private let isSelf: Bool?
    /// Whether the sender's name goes above the bubble.
    private let showsSenderName: Bool
    private let maxBubbleWidth: CGFloat
    @State private var expandedMessageIDs: Set<String> = []
    @State private var showDeliveryDetail = false

    init(
        message: BitchatMessage,
        isSelf: Bool? = nil,
        showsSenderName: Bool = false,
        maxBubbleWidth: CGFloat = .infinity
    ) {
        self.message = message
        self.deliveryStatus = message.deliveryStatus
        self.isSelf = isSelf
        self.showsSenderName = showsSenderName
        self.maxBubbleWidth = maxBubbleWidth
    }

    var body: some View {
        let isSelf = self.isSelf ?? conversationUIModel.isSentByCurrentUser(message)
        // Heavy token scans run once per message, not once per render
        let scan = message.contentScan
        let text = conversationUIModel.formatMessageBody(message, isSelf: isSelf, colorScheme: colorScheme)
        let hasChips = !scan.lightningLinks.isEmpty || !scan.cashuLinks.isEmpty
        let showsDeliveryStatus = isSelf && message.isPrivate && deliveryStatus != .notSentYet

        VStack(alignment: isSelf ? .trailing : .leading, spacing: 3) {
            if showsSenderName && !isSelf {
                MessageSenderNameView(message: message)
            }
            MessageBubbleLayout(isSelf: isSelf, maxBubbleWidth: maxBubbleWidth) {
                // A message of payment tokens only has no text to bubble:
                // its chips take the bubble's place.
                if text.characters.isEmpty && hasChips {
                    paymentChips(scan)
                } else {
                    bubble(text, isSelf: isSelf, scan: scan)
                }
                MessageMetaView(
                    message: message,
                    showsVerifiedSeal: !isSelf && conversationUIModel.showsVerifiedSeal(for: message),
                    deliveryStatus: showsDeliveryStatus ? deliveryStatus : nil,
                    showsDeliveryDetail: $showDeliveryDetail
                )
            }
            if showsDeliveryStatus {
                MessageDeliveryCaption(status: deliveryStatus, showsDetail: showDeliveryDetail)
            }
            if hasChips && !text.characters.isEmpty {
                paymentChips(scan)
                    .padding(.top, 3)
            }
        }
        // Collapse the revealed caption when the status advances (e.g.
        // sending → sent → delivered) so a detail opened for one state
        // doesn't linger and silently morph into another. Guarded write:
        // under a message storm many rows change status within one frame,
        // and an unconditional state write per change trips SwiftUI's
        // "tried to update multiple times per frame" re-entrancy warning.
        .onChange(of: deliveryStatus) { _ in
            if showDeliveryDetail {
                showDeliveryDetail = false
            }
        }
    }

    private func bubble(_ text: AttributedString, isSelf: Bool, scan: BitchatMessage.ContentScan) -> some View {
        let isExpanded = expandedMessageIDs.contains(message.id)
        return VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(scan.isLongForDisplay && !isExpanded ? TransportConfig.uiLongMessageLineLimit : nil)

            // Expand/Collapse for very long messages
            if scan.isLongForDisplay {
                let labelKey = isExpanded ? LocalizedStringKey("content.message.show_less") : LocalizedStringKey("content.message.show_more")
                Button(labelKey) {
                    if isExpanded { expandedMessageIDs.remove(message.id) }
                    else { expandedMessageIDs.insert(message.id) }
                }
                .bitchatFont(size: 11, weight: .medium)
                .foregroundColor(isSelf ? Color.white.opacity(0.85) : palette.accentBlue)
            }
        }
        .padding(MessageBubbleStyle.textInsets)
        .messageBubbleBackground(isSelf: isSelf, palette: palette)
        // Links take the tint: white on my accent bubble.
        .tint(isSelf ? .white : palette.accentBlue)
    }

    /// Lightning and Cashu payments as tappable chips.
    private func paymentChips(_ scan: BitchatMessage.ContentScan) -> some View {
        HStack(spacing: 8) {
            ForEach(scan.lightningLinks, id: \.self) { link in
                PaymentChipView(paymentType: .lightning(link))
            }
            ForEach(scan.cashuLinks, id: \.self) { link in
                PaymentChipView(paymentType: .cashu(link))
            }
        }
    }
}

// Wrapped in #if DEBUG because the preview depends on _PreviewHelpers
// (PreviewKeychainManager, BitchatMessage.preview), a development asset
// excluded from archive builds.
#if DEBUG
#Preview {
    let keychain = PreviewKeychainManager()
    let viewModel = ChatViewModel(
        keychain: keychain,
        idBridge: NostrIdentityBridge(),
        identityManager: SecureIdentityStateManager(keychain)
    )
    let privateConversationModel = PrivateConversationModel(
        chatViewModel: viewModel,
        conversations: viewModel.conversations
    )
    let conversationUIModel = ConversationUIModel(
        chatViewModel: viewModel,
        privateConversationModel: privateConversationModel,
        conversations: viewModel.conversations
    )
    
    Group {
        List {
            TextMessageView(message: .preview)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(EmptyView())
        }
        .environment(\.colorScheme, .light)
        
        List {
            TextMessageView(message: .preview)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(EmptyView())
        }
        .environment(\.colorScheme, .dark)
    }
    .environmentObject(conversationUIModel)
}
#endif
