//
//  MediaMessageView.swift
//  bitchat
//
//  Created by Islam on 30/03/2026.
//

import SwiftUI
import BitFoundation

struct MediaMessageView: View {
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @Environment(\.resolvedMessageBubbleColor) private var bubbleColor
    @ThemedPalette private var palette
    let message: BitchatMessage
    let media: BitchatMessage.Media
    /// Value snapshot of the message's mutable delivery status, captured at
    /// construction (see `TextMessageView.deliveryStatus`): `BitchatMessage`
    /// is a reference type mutated in place, and SwiftUI compares reference
    /// fields by identity, so without the snapshot a status-only change
    /// (send progress, delivered → read) would not re-render this row.
    private let deliveryStatus: DeliveryStatus
    /// Whether I sent the media, which puts it on the right. Nil asks the
    /// model; the list passes the answer it already has.
    private let isSelf: Bool?
    /// Whether the sender's name goes above the media.
    private let showsSenderName: Bool
    private let maxBubbleWidth: CGFloat
    @State private var showDeliveryDetail = false
    /// Settings toggle: images from favorite contacts skip the blur.
    @AppStorage(MediaRevealSettings.autoRevealFavoritesKey) private var autoRevealFavorites = false

    @Binding var imagePreviewURL: URL?

    init(
        message: BitchatMessage,
        media: BitchatMessage.Media,
        imagePreviewURL: Binding<URL?>,
        isSelf: Bool? = nil,
        showsSenderName: Bool = false,
        maxBubbleWidth: CGFloat = .infinity
    ) {
        self.message = message
        self.media = media
        self.deliveryStatus = message.deliveryStatus
        self._imagePreviewURL = imagePreviewURL
        self.isSelf = isSelf
        self.showsSenderName = showsSenderName
        self.maxBubbleWidth = maxBubbleWidth
    }

    var body: some View {
        let isFromMe = isSelf ?? conversationUIModel.isMediaMessageFromCurrentUser(message)
        let state = mediaSendState(for: deliveryStatus, isFromMe: isFromMe)
        let showsDeliveryStatus = isFromMe && message.isPrivate && deliveryStatus != .notSentYet

        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 3) {
            if showsSenderName && !isFromMe {
                MessageSenderNameView(message: message)
            }
            MessageBubbleLayout(isSelf: isFromMe, maxBubbleWidth: maxBubbleWidth) {
                mediaContent(isFromMe: isFromMe, state: state)
                    .padding(4)
                    .messageBubbleBackground(isSelf: isFromMe, palette: palette, hasTail: false, selfFill: bubbleColor.color)
                MessageMetaView(
                    message: message,
                    showsVerifiedSeal: !isFromMe && conversationUIModel.showsVerifiedSeal(for: message),
                    deliveryStatus: showsDeliveryStatus ? deliveryStatus : nil,
                    showsDeliveryDetail: $showDeliveryDetail
                )
            }
            .alignmentGuide(.messageBubbleBottom) { $0[.bottom] }
            if showsDeliveryStatus {
                MessageDeliveryCaption(status: deliveryStatus, showsDetail: showDeliveryDetail)
            }
        }
        .padding(.vertical, 2)
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

    /// The voice note or image itself. Each draws its own rounded card, so
    /// it stands in for the bubble.
    @ViewBuilder
    private func mediaContent(
        isFromMe: Bool,
        state: (isSending: Bool, progress: Double?, canCancel: Bool)
    ) -> some View {
        let cancelAction: (() -> Void)? = state.canCancel ? { conversationUIModel.cancelMediaSend(messageID: message.id) } : nil
        switch media {
        case .voice(let url):
            VoiceNoteView(
                url: url,
                isSending: state.isSending,
                sendProgress: state.progress,
                isLive: conversationUIModel.isLiveVoiceMessage(message),
                foregroundColor: isFromMe ? .white : .primary,
                onCancel: cancelAction
            )
            .frame(maxWidth: 320)
        case .image(let url):
            BlockRevealImageView(
                url: url,
                revealProgress: state.progress,
                isSending: state.isSending,
                onCancel: cancelAction,
                initiallyBlurred: !isFromMe && !(autoRevealFavorites && conversationUIModel.isFavoriteSender(of: message)),
                onOpen: {
                    if !state.isSending {
                        imagePreviewURL = url
                    }
                },
                onDelete: !isFromMe ? { conversationUIModel.deleteMediaMessage(messageID: message.id) } : nil
            )
            .frame(maxWidth: 280)
        }
    }

    private func mediaSendState(for deliveryStatus: DeliveryStatus, isFromMe: Bool) -> (isSending: Bool, progress: Double?, canCancel: Bool) {
        // A received message is never in a send state: BitchatMessage defaults
        // private messages to .sending, so an incoming message's status must
        // not drive the reveal mask or disable the reveal tap.
        guard isFromMe else { return (false, nil, false) }
        var isSending = false
        var progress: Double?
        switch deliveryStatus {
        case .sending:
            isSending = true
            progress = 0
        case .partiallyDelivered(let reached, let total):
            if total > 0 {
                isSending = true
                progress = Double(reached) / Double(total)
            }
        case .notSentYet, .sent, .carried, .read, .delivered, .failed:
            break
        }
        // Only my own sends get this far, so any in-flight one can cancel.
        let canCancel = isSending
        let clamped = progress.map { max(0, min(1, $0)) }
        return (isSending, isSending ? clamped : nil, canCancel)
    }
}
