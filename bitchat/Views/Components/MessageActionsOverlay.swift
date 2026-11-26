//
// MessageActionsOverlay.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// Where the long-press overlay puts its three parts, in screen points:
/// the emoji bar, the message and the action card, stacked in that order.
/// The message stays where it was when everything fits. Otherwise the stack
/// slides just enough to stay on screen, and a message too tall to fit is
/// cut to the height that is left.
struct MessageActionsLayout: Equatable {
    let bar: CGRect
    let message: CGRect
    let card: CGRect
    /// Whether the message shows only its top part.
    let isMessageClipped: Bool

    static let spacing: CGFloat = 10
    static let margin: CGFloat = 12
    /// The shortest a cut message gets.
    static let minimumMessageHeight: CGFloat = 60

    init(
        screen: CGRect,
        safeArea: EdgeInsets,
        messageFrame: CGRect,
        isSelf: Bool,
        barSize: CGSize,
        cardSize: CGSize
    ) {
        let usable = CGRect(
            x: screen.minX + safeArea.leading + Self.margin,
            y: screen.minY + safeArea.top + Self.margin,
            width: max(0, screen.width - safeArea.leading - safeArea.trailing - 2 * Self.margin),
            height: max(0, screen.height - safeArea.top - safeArea.bottom - 2 * Self.margin)
        )
        let hasBar = barSize.height > 0
        let barBlock = hasBar ? barSize.height + Self.spacing : 0
        let cardBlock = cardSize.height + Self.spacing
        let roomForMessage = usable.height - barBlock - cardBlock
        let messageHeight = min(messageFrame.height, max(roomForMessage, Self.minimumMessageHeight))
        let total = barBlock + messageHeight + cardBlock

        // Keep the message in place, then slide the stack onto the screen.
        var top = messageFrame.minY - barBlock
        top = min(top, usable.maxY - total)
        top = max(top, usable.minY)

        func aligned(width: CGFloat) -> CGFloat {
            let x = isSelf ? messageFrame.maxX - width : messageFrame.minX
            return min(max(x, usable.minX), max(usable.minX, usable.maxX - width))
        }

        bar = CGRect(x: aligned(width: barSize.width), y: top, width: barSize.width, height: barSize.height)
        message = CGRect(x: messageFrame.minX, y: top + barBlock, width: messageFrame.width, height: messageHeight)
        card = CGRect(x: aligned(width: cardSize.width), y: message.maxY + Self.spacing, width: cardSize.width, height: cardSize.height)
        isMessageClipped = messageHeight < messageFrame.height
    }
}

/// What the long-press overlay shows for one message.
struct MessageActionsOverlayItem: Identifiable {
    let message: BitchatMessage
    /// The message row's frame on screen when it was pressed.
    let messageFrame: CGRect
    let isSelf: Bool
    /// Whether the emoji bar shows: a location message that never went out
    /// has no event to react to.
    let canReact: Bool
    let selectedReactions: Set<String>
    let actions: [MessageAction]
    /// The message as its row draws it.
    let content: AnyView

    var id: String { message.id }
}

/// The long-press overlay on iOS, after Instagram's and the system's
/// context menus but in Liquid Glass: the chat blurs and dims, the pressed
/// message lifts in place, a glass capsule of quick reactions (and a "+"
/// for every emoji) sits above it, and a glass card of actions below it,
/// headed by the message's time. A tap outside, a swipe down, or picking
/// anything closes it.
struct MessageActionsOverlay: View {
    let item: MessageActionsOverlayItem
    let tint: MessageBubbleColor
    let onReact: (String) -> Void
    let onOpenPicker: () -> Void
    /// Called once the closing animation is done; removes the overlay.
    let onDismiss: () -> Void
    /// The screen's safe area; read from the window when nil.
    var safeArea: EdgeInsets?
    /// Starts fully shown, without the opening animation (snapshots).
    var startsShown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShown = false
    @State private var isClosing = false
    @State private var dragOffset: CGFloat = 0
    @State private var barSize = CGSize(width: 324, height: 56)
    @State private var cardSize = CGSize(width: 250, height: 200)

    init(
        item: MessageActionsOverlayItem,
        tint: MessageBubbleColor,
        onReact: @escaping (String) -> Void,
        onOpenPicker: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        safeArea: EdgeInsets? = nil,
        startsShown: Bool = false
    ) {
        self.item = item
        self.tint = tint
        self.onReact = onReact
        self.onOpenPicker = onOpenPicker
        self.onDismiss = onDismiss
        self.safeArea = safeArea
        self.startsShown = startsShown
        // Shown from the first frame, so no opening animation runs.
        _isShown = State(initialValue: startsShown)
    }

    var body: some View {
        GeometryReader { proxy in
            let screen = CGRect(origin: .zero, size: proxy.size)
            let insets = safeArea ?? Self.windowSafeArea
            let layout = MessageActionsLayout(
                screen: screen,
                safeArea: insets,
                messageFrame: item.messageFrame,
                isSelf: item.isSelf,
                barSize: item.canReact ? barSize : .zero,
                cardSize: cardSize
            )
            let barWidthLimit = screen.width - insets.leading - insets.trailing - 2 * MessageActionsLayout.margin
            ZStack(alignment: .topLeading) {
                backdrop
                lifted(layout: layout)
                if item.canReact {
                    emojiBar(widthLimit: barWidthLimit)
                        .measure($barSize)
                        .scaleEffect(appearScale, anchor: item.isSelf ? .bottomTrailing : .bottomLeading)
                        .opacity(isShown ? 1 : 0)
                        .position(x: layout.bar.midX, y: layout.bar.midY)
                        .offset(y: dragOffset * 0.6)
                }
                actionCard
                    .measure($cardSize)
                    .scaleEffect(appearScale, anchor: item.isSelf ? .topTrailing : .topLeading)
                    .opacity(isShown ? 1 : 0)
                    .position(x: layout.card.midX, y: layout.card.midY)
                    .offset(y: dragOffset * 0.6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(swipeDown)
        .accessibilityAction(.escape) { close() }
        .onAppear {
            guard !isShown else { return }
            withAnimation(openingAnimation) { isShown = true }
        }
    }

    // MARK: Parts

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(colorScheme == .dark ? 0.38 : 0.16)
        }
        .opacity(isShown ? max(0, 1 - dragOffset / 400) : 0)
        .onTapGesture { close() }
        .accessibilityHidden(true)
    }

    /// The pressed message, lifted where it was (or slid to make room),
    /// cut with a soft edge when it is too tall.
    private func lifted(layout: MessageActionsLayout) -> some View {
        let frame = isShown ? layout.message : CGRect(origin: item.messageFrame.origin, size: layout.message.size)
        return item.content
            .frame(width: layout.message.width, height: item.messageFrame.height, alignment: .top)
            .frame(width: layout.message.width, height: layout.message.height, alignment: .top)
            .clipped()
            .mask {
                if layout.isMessageClipped {
                    LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle()
                }
            }
            .scaleEffect(isShown && !reduceMotion ? 1.03 : 1)
            .shadow(color: .black.opacity(isShown ? 0.22 : 0), radius: 18, y: 8)
            .position(x: frame.midX, y: frame.midY)
            .offset(y: dragOffset * 0.6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func emojiBar(widthLimit: CGFloat) -> some View {
        let count = CGFloat(MessageReaction.emojis.count + 1)
        let cell = min(46, max(34, (widthLimit - 16) / count))
        return HStack(spacing: 0) {
            ForEach(Array(MessageReaction.emojis.enumerated()), id: \.element) { index, emoji in
                let isSelected = item.selectedReactions.contains(emoji)
                Button {
                    close { onReact(emoji) }
                } label: {
                    EmojiGlyph(emoji: emoji, side: cell * 0.7)
                        .frame(width: cell, height: cell)
                        .background {
                            if isSelected {
                                Circle().fill(tint.color.opacity(colorScheme == .dark ? 0.6 : 0.25))
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(OverlayPressStyle())
                .scaleEffect(isShown || reduceMotion ? 1 : 0.3)
                .animation(popAnimation(index: index), value: isShown)
                .accessibilityLabel(Text(verbatim: emoji))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
            Button {
                close { onOpenPicker() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: cell * 0.42, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: cell, height: cell)
                    .contentShape(Circle())
            }
            .buttonStyle(OverlayPressStyle())
            .scaleEffect(isShown || reduceMotion ? 1 : 0.3)
            .animation(popAnimation(index: MessageReaction.emojis.count), value: isShown)
            .accessibilityLabel(String(localized: "content.reaction.add", comment: "Menu item or title for adding a reaction to a message"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .reactionGlassSurface(in: Capsule(), interactive: true)
        .fixedSize()
    }

    private var actionCard: some View {
        let primary = item.actions.filter(\.isPrimary)
        let rest = item.actions.filter { !$0.isPrimary }
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: MessageTimeLabel.exactLabel(for: item.message.timestamp))
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(primary) { action in
                Button {
                    close { action.perform() }
                } label: {
                    OverlayActionRow(title: action.title, systemImage: action.systemImage, isDestructive: action.isDestructive)
                }
                .buttonStyle(OverlayRowStyle())
            }
            if !rest.isEmpty {
                Menu {
                    ForEach(rest) { action in
                        Button(role: action.isDestructive ? .destructive : nil) {
                            close { action.perform() }
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    OverlayActionRow(
                        title: String(localized: "content.actions.more", comment: "Row in the message actions that shows the remaining actions"),
                        systemImage: "ellipsis",
                        isDestructive: false,
                        showsChevron: true
                    )
                }
                .buttonStyle(OverlayRowStyle())
            }
        }
        .padding(.bottom, 6)
        .frame(width: 252, alignment: .leading)
        .reactionGlassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Motion

    private var appearScale: CGFloat {
        isShown || reduceMotion ? 1 : 0.6
    }

    private var openingAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    private func popAnimation(index: Int) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.34, dampingFraction: 0.58).delay(0.04 + Double(index) * 0.03)
    }

    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 90 || value.predictedEndTranslation.height > 240 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }

    /// Animates the overlay out, then removes it and runs `then`.
    private func close(then action: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.9)) {
            isShown = false
            dragOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onDismiss()
            action?()
        }
    }

    private static var windowSafeArea: EdgeInsets {
        #if os(iOS)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        let insets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
        #else
        return EdgeInsets()
        #endif
    }
}

/// A row of the action card: an icon and a label, like a menu item.
private struct OverlayActionRow: View {
    let title: String
    let systemImage: String
    let isDestructive: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.regular))
                .frame(width: 24)
            Text(title)
                .font(.body)
                .lineLimit(2)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
        .padding(.horizontal, 20)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }
}

/// Highlights a pressed card row.
private struct OverlayRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0))
    }
}

/// Presses an emoji in a little.
private struct OverlayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private extension View {
    /// Writes the view's size into `size` as it lays out.
    func measure(_ size: Binding<CGSize>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { size.wrappedValue = proxy.size }
                    .onChange(of: proxy.size) { size.wrappedValue = $0 }
            }
        }
    }
}
