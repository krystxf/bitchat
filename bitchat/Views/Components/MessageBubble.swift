//
// MessageBubble.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Geometry and colors every chat bubble shares.
enum MessageBubbleStyle {
    static let cornerRadius: CGFloat = 18
    /// Share of the row's width a bubble may fill.
    static let maxWidthFraction: CGFloat = 0.75
    /// Inset of the text inside a bubble. The sender's name above a bubble
    /// lines up with its text.
    static let textInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Widest bubble in a row of `rowWidth`.
    static func maxBubbleWidth(rowWidth: CGFloat) -> CGFloat {
        max(0, rowWidth) * maxWidthFraction
    }

    /// Fill of other people's bubbles: a translucent neutral system fill,
    /// so the backdrop's tint shows through as it does under the chrome.
    static var incomingFill: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemFill)
        #else
        if #available(macOS 14.0, *) {
            return Color(NSColor.secondarySystemFill)
        }
        return Color(NSColor.quaternaryLabelColor)
        #endif
    }
}

extension View {
    /// Draws a chat bubble behind the view: the accent color behind mine,
    /// a neutral fill behind everyone else's.
    func messageBubbleBackground(isSelf: Bool, palette: ThemePalette) -> some View {
        background(
            MessageBubbleStyle.shape
                .fill(isSelf ? palette.accent : MessageBubbleStyle.incomingFill)
        )
    }
}

/// Puts a bubble and its meta (status glyphs) side by side, bottom-aligned,
/// with the meta on the inner side: right of other people's bubbles, left
/// of mine. The bubble hugs its content up to `maxBubbleWidth`; the meta
/// keeps its ideal size.
///
/// Stacks can't do this. An HStack offers a wrapping text only a share of
/// the width, and a `maxWidth` frame grows to its maximum, which pushes the
/// meta away from a short bubble. Empty meta takes no room.
struct MessageBubbleLayout: Layout {
    let isSelf: Bool
    let maxBubbleWidth: CGFloat
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(proposal, subviews)
        return CGSize(
            width: sizes.bubble.width + sizes.metaSpan,
            height: max(sizes.bubble.height, sizes.meta.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else { return }
        let sizes = measure(proposal, subviews)
        let bubbleX = isSelf ? bounds.maxX - sizes.bubble.width : bounds.minX
        bubble.place(
            at: CGPoint(x: bubbleX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(sizes.bubble)
        )
        guard subviews.count > 1 else { return }
        let metaX = isSelf
            ? bubbleX - spacing - sizes.meta.width
            : bubbleX + sizes.bubble.width + spacing
        subviews[1].place(
            at: CGPoint(x: metaX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(sizes.meta)
        )
    }

    private func measure(
        _ proposal: ProposedViewSize,
        _ subviews: Subviews
    ) -> (bubble: CGSize, meta: CGSize, metaSpan: CGFloat) {
        guard let bubble = subviews.first else { return (.zero, .zero, 0) }
        let meta = subviews.count > 1 ? subviews[1].sizeThatFits(.unspecified) : .zero
        let metaSpan = meta.width > 0 ? meta.width + spacing : 0
        let available = (proposal.width ?? .infinity) - metaSpan
        let bubbleWidth = max(0, min(available, maxBubbleWidth))
        let bubbleSize = bubble.sizeThatFits(ProposedViewSize(width: bubbleWidth, height: nil))
        return (bubbleSize, meta, metaSpan)
    }
}

/// What sits beside a bubble: the private lock, the verified seal, the
/// bridge glyph, and the delivery status of my private messages. The time
/// is not here: it heads each time group instead (`MessageTimeHeader`).
/// The status is tappable: `.help()` tooltips only exist on macOS, so iOS
/// users get its description as a caption under the bubble instead.
struct MessageMetaView: View {
    let message: BitchatMessage
    let showsVerifiedSeal: Bool
    /// The delivery status to show, or nil for none.
    let deliveryStatus: DeliveryStatus?
    @Binding var showsDeliveryDetail: Bool

    var body: some View {
        HStack(spacing: 3) {
            if message.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.bitchatSystem(size: 8))
                    .foregroundColor(Color.orange.opacity(0.75))
                    .accessibilityHidden(true)
            }
            if showsVerifiedSeal {
                Image(systemName: "checkmark.seal.fill")
                    .font(.bitchatSystem(size: 9))
                    .foregroundColor(Color.green.opacity(0.85))
                    .accessibilityLabel(
                        String(localized: "content.accessibility.verified_sender", defaultValue: "Verified sender", comment: "Accessibility label for the seal next to a verified peer's name on a private message")
                    )
            }
            if message.isBridged {
                Image(systemName: "network")
                    .font(.bitchatSystem(size: 8))
                    .foregroundColor(Color.cyan.opacity(0.75))
                    .accessibilityLabel(
                        String(localized: "content.accessibility.bridged_message", defaultValue: "Arrived across a mesh bridge", comment: "Accessibility label for the glyph marking a message that arrived across a mesh bridge")
                    )
            }
            if let deliveryStatus {
                Button {
                    showsDeliveryDetail.toggle()
                } label: {
                    DeliveryStatusView(status: deliveryStatus)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    String(localized: "content.accessibility.delivery_detail_hint", comment: "Accessibility hint for the delivery status glyph explaining a tap reveals details")
                )
            }
        }
        .padding(.bottom, 2)
    }
}

/// The sender's name above someone else's bubble, where several people
/// talk. It carries the same link as the name in the full text, so a tap
/// opens the sender's actions.
struct MessageSenderNameView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @ThemedPalette private var palette

    let message: BitchatMessage

    var body: some View {
        Text(conversationUIModel.formatSenderName(message, colorScheme: colorScheme))
            // The name is a link; keep it in the label color wherever links
            // would take the tint.
            .tint(palette.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, MessageBubbleStyle.textInsets.leading)
    }
}

/// The delivery caption under my private bubble: a failure reason always,
/// any other status once its glyph is tapped.
struct MessageDeliveryCaption: View {
    @ThemedPalette private var palette

    let status: DeliveryStatus
    let showsDetail: Bool

    var body: some View {
        if case .failed = status {
            caption(color: Color.red.opacity(0.9))
        } else if showsDetail {
            caption(color: palette.secondary)
        }
    }

    private func caption(color: Color) -> some View {
        Text(verbatim: status.bitchatDescription)
            .bitchatFont(size: 11)
            .foregroundColor(color)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Which rows open a new run of bubbles. A run is consecutive messages
/// from one sender, close in time. Only its first row shows the sender's
/// name and keeps the wider gap above it.
enum MessageRunPolicy {
    /// Longest pause within one run.
    static let maxGap: TimeInterval = 5 * 60

    static func startsRun(_ message: BitchatMessage, after previous: BitchatMessage?) -> Bool {
        guard let previous else { return true }
        if message.sender == "system" || previous.sender == "system" { return true }
        if message.isArchivedEcho != previous.isArchivedEcho { return true }
        guard message.senderPeerID == previous.senderPeerID,
              message.sender == previous.sender
        else { return true }
        return abs(message.timestamp.timeIntervalSince(previous.timestamp)) > maxGap
    }
}
