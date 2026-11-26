//
// MessageReactionViews.swift
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

// MARK: - Model

/// One emoji's reactions on a message, as its pill shows them.
struct MessageReactionSummary: Identifiable, Equatable {
    let emoji: String
    /// The other people who reacted, by display name, sorted.
    let otherNames: [String]
    /// Whether I am among them.
    let includesMe: Bool

    var id: String { emoji }
    var count: Int { otherNames.count + (includesMe ? 1 : 0) }
}

/// The reactions of a timeline, aggregated once per render: every message's
/// pills, in the order each emoji first reached the message, so a pill
/// never jumps when another one changes.
struct MessageReactionProjection {
    private(set) var summariesByTarget: [String: [MessageReactionSummary]] = [:]

    init(
        messages: [BitchatMessage],
        isMine: (BitchatMessage) -> Bool,
        displayName: (BitchatMessage) -> String
    ) {
        let events = MessageReaction.resolvedEvents(in: messages)
        guard !events.isEmpty else { return }
        var owners: [String: [String: [String: (name: String, isMine: Bool)]]] = [:]
        var order: [String: [String]] = [:]
        for item in events {
            let target = item.event.targetID
            let emoji = item.event.emoji
            let owner = item.message.senderPeerID?.id ?? item.message.sender
            var emojiOwners = owners[target, default: [:]][emoji, default: [:]]
            if item.event.removes {
                emojiOwners.removeValue(forKey: owner)
            } else {
                emojiOwners[owner] = (displayName(item.message), isMine(item.message))
                if !order[target, default: []].contains(emoji) {
                    order[target, default: []].append(emoji)
                }
            }
            owners[target, default: [:]][emoji] = emojiOwners
        }
        for (target, emojis) in order {
            let summaries = emojis.compactMap { emoji -> MessageReactionSummary? in
                guard let actors = owners[target]?[emoji], !actors.isEmpty else { return nil }
                return MessageReactionSummary(
                    emoji: emoji,
                    otherNames: actors.values.filter { !$0.isMine }.map(\.name).sorted {
                        $0.localizedStandardCompare($1) == .orderedAscending
                    },
                    includesMe: actors.values.contains(where: \.isMine)
                )
            }
            if !summaries.isEmpty {
                summariesByTarget[target] = summaries
            }
        }
    }

    func summaries(for messageID: String) -> [MessageReactionSummary] {
        summariesByTarget[messageID] ?? []
    }
}

/// Who reacted, as people read it: "You", "Alice and Bob",
/// "You, Alice and Bob", "Alice, Bob and 3 Others". The list pattern is
/// the locale's own (`ListFormatter`).
enum MessageReactionNames {
    /// Names shown before the rest collapse into "N Others".
    static let maxNamesShown = 3

    static func list(
        otherNames: [String],
        includesMe: Bool,
        you: String = String(localized: "content.reaction.you", comment: "Stands for me in the list of people who reacted to a message"),
        others: (Int) -> String = { count in
            String(
                format: String(localized: "content.reaction.others_count", comment: "The rest of the people who reacted, after the names shown; the number is at least 2"),
                locale: .current,
                count
            )
        }
    ) -> String {
        var names = otherNames
        if includesMe {
            names.insert(you, at: 0)
        }
        if names.count > maxNamesShown {
            let shown = Array(names.prefix(maxNamesShown - 1))
            names = shown + [others(names.count - shown.count)]
        }
        return ListFormatter.localizedString(byJoining: names)
    }

    /// "Alice and Bob reacted with 👍".
    static func sentence(for summary: MessageReactionSummary) -> String {
        String(
            format: String(localized: "content.accessibility.reaction_names", comment: "Tooltip naming the people who reacted with an emoji"),
            locale: .current,
            list(otherNames: summary.otherNames, includesMe: summary.includesMe),
            summary.emoji
        )
    }
}

// MARK: - Style

/// Sizes and colors the reaction pills share.
enum MessageReactionStyle {
    /// Gap between pills, both ways.
    static let spacing: CGFloat = 6
    /// Gap between a bubble and its pills.
    static let bubbleGap: CGFloat = 3

    /// A spring for pills coming and going, or a plain fade with Reduce
    /// Motion.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.78)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
    }

    /// The text color of a pill that holds my reaction: the chat's message
    /// color, lifted toward white in dark mode so it reads on a dark pill.
    static func ownTint(_ color: MessageBubbleColor, colorScheme: ColorScheme) -> Color {
        guard colorScheme == .dark else { return color.color }
        let rgb = color.rgb
        let lift = 0.45
        return Color(
            .sRGB,
            red: rgb.red + (1 - rgb.red) * lift,
            green: rgb.green + (1 - rgb.green) * lift,
            blue: rgb.blue + (1 - rgb.blue) * lift,
            opacity: 1
        )
    }
}

/// The capsule behind a pill. Neutral pills sit on a frosted material
/// with an opaque-enough tint that they read on every chat background:
/// the gradients, OLED black and photos. My pills add a soft wash of the
/// message color and a thin stroke in it.
struct ReactionPillBackground: View {
    let isMine: Bool
    let tint: MessageBubbleColor
    var isHighlighted = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            Capsule().fill(.regularMaterial)
            Capsule().fill(isDark ? Color(white: 0.17).opacity(0.78) : Color.white.opacity(0.74))
            if isMine {
                Capsule().fill(tint.color.opacity(isDark ? 0.34 : 0.14))
            }
            if isHighlighted {
                Capsule().fill(Color.primary.opacity(0.08))
            }
        }
        .overlay {
            if isMine {
                Capsule().strokeBorder(MessageReactionStyle.ownTint(tint, colorScheme: colorScheme).opacity(0.9), lineWidth: 1)
            } else {
                Capsule().strokeBorder(Color.primary.opacity(isDark ? 0.14 : 0.10), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(isDark ? 0.0 : 0.06), radius: 1.5, y: 0.5)
    }
}

/// Presses a pill in a little, as a system button does.
private struct ReactionPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pills

/// The pills under a bubble: one per emoji, then the add pill. Rows wrap
/// and line up with the bubble's edge: the leading edge under other
/// people's bubbles, the trailing edge under mine.
struct MessageReactionsView: View {
    let summaries: [MessageReactionSummary]
    let isSelf: Bool
    /// The bubble's widest: rows wrap within it.
    let maxWidth: CGFloat
    let tint: MessageBubbleColor
    let onToggle: (String) -> Void
    /// iOS: opens the full emoji picker in a sheet. macOS anchors it to the
    /// add pill instead.
    var onOpenPicker: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ReactionFlowLayout(spacing: MessageReactionStyle.spacing, alignment: isSelf ? .trailing : .leading, maxWidth: maxWidth) {
            ForEach(summaries) { summary in
                ReactionPill(summary: summary, tint: tint) {
                    onToggle(summary.emoji)
                }
                .transition(MessageReactionStyle.transition(reduceMotion: reduceMotion))
            }
            ReactionAddPill(
                selected: Set(summaries.filter(\.includesMe).map(\.emoji)),
                tint: tint,
                onSelect: onToggle,
                onOpenPicker: onOpenPicker
            )
        }
        .animation(MessageReactionStyle.animation(reduceMotion: reduceMotion), value: summaries)
    }
}

/// One emoji with its count. A tap adds or takes back my reaction; a long
/// press (iOS), a secondary click and a hover tooltip (macOS) tell who
/// reacted.
struct ReactionPill: View {
    let summary: MessageReactionSummary
    let tint: MessageBubbleColor
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 26
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding: CGFloat = 8
    /// The emoji's square: every emoji fits it, a wide family or flag too.
    @ScaledMetric(relativeTo: .subheadline) private var emojiSide: CGFloat = 18
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                EmojiGlyph(emoji: summary.emoji, side: emojiSide)
                Text(summary.count, format: .number)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(summary.includesMe ? MessageReactionStyle.ownTint(tint, colorScheme: colorScheme) : Color.secondary)
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background(ReactionPillBackground(isMine: summary.includesMe, tint: tint, isHighlighted: isHovered))
            .contentShape(Capsule())
            .reactionHitTarget()
        }
        .buttonStyle(ReactionPillButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: summary.count)
        #if os(macOS)
        .onHover { isHovered = $0 }
        .help(MessageReactionNames.sentence(for: summary))
        #endif
        .contextMenu {
            Section(MessageReactionNames.sentence(for: summary)) {
                Button(action: action) {
                    if summary.includesMe {
                        Label(String(localized: "content.reaction.remove", comment: "Menu item that takes back my reaction with this emoji"), systemImage: "minus.circle")
                    } else {
                        Label(String(localized: "content.reaction.add", comment: "Menu item or title for adding a reaction to a message"), systemImage: "plus.circle")
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: String(localized: "content.accessibility.reaction", comment: "VoiceOver label for a reaction badge, with the number of people and emoji"),
            locale: .current,
            summary.count,
            summary.emoji
        ))
        .accessibilityValue(MessageReactionNames.list(otherNames: summary.otherNames, includesMe: summary.includesMe))
        .accessibilityAddTraits(summary.includesMe ? [.isButton, .isSelected] : .isButton)
    }
}

/// The pill that opens the full emoji picker: a sheet on iOS, a popover
/// anchored to the pill on macOS.
struct ReactionAddPill: View {
    let selected: Set<String>
    let tint: MessageBubbleColor
    let onSelect: (String) -> Void
    let onOpenPicker: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 26
    @State private var showsPicker = false
    @State private var isHovered = false

    var body: some View {
        Button {
            #if os(macOS)
            showsPicker = true
            #else
            onOpenPicker()
            #endif
        } label: {
            // A smiley with a small plus at its shoulder, the usual "add
            // reaction" sign; the plus sits clear of the face.
            Image(systemName: "face.smiling")
                .symbolRenderingMode(.monochrome)
                .font(.subheadline.weight(.medium))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.heavy))
                        .imageScale(.small)
                        .offset(x: 6, y: -3)
                }
                .foregroundStyle(Color.secondary)
                .padding(.trailing, 3)
                .frame(minWidth: height + 10, minHeight: height)
                .background(ReactionPillBackground(isMine: false, tint: tint, isHighlighted: isHovered))
                .contentShape(Capsule())
                .reactionHitTarget()
        }
        .buttonStyle(ReactionPillButtonStyle())
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityLabel(String(localized: "content.accessibility.add_reaction", comment: "Accessibility label for opening the emoji reaction picker"))
        #if os(macOS)
        .reactionPickerPopover(isPresented: $showsPicker, selected: selected, tint: tint, onSelect: onSelect)
        #endif
    }
}

private extension View {
    /// Widens the tap area to 44 pt tall on iOS without making the pill
    /// bigger: the hit shape reaches into the gaps around it.
    @ViewBuilder
    func reactionHitTarget() -> some View {
        #if os(iOS)
        self
            .padding(.vertical, 9)
            .padding(.horizontal, MessageReactionStyle.spacing / 2)
            .contentShape(Rectangle())
            .padding(.vertical, -9)
            .padding(.horizontal, -MessageReactionStyle.spacing / 2)
        #else
        self
        #endif
    }
}

// MARK: - Choices

/// The reactions to choose from, my current ones marked: the row the add
/// pill opens, and the quick bar on macOS.
struct ReactionChoicesRow: View {
    let selected: Set<String>
    let tint: MessageBubbleColor
    var emojiSize: CGFloat = 26
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MessageReaction.emojis, id: \.self) { emoji in
                ReactionChoiceButton(emoji: emoji, isSelected: selected.contains(emoji), tint: tint, size: emojiSize) {
                    onSelect(emoji)
                }
            }
        }
    }
}

private struct ReactionChoiceButton: View {
    let emoji: String
    let isSelected: Bool
    let tint: MessageBubbleColor
    let size: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            EmojiGlyph(emoji: emoji, side: size * 1.2)
                .frame(width: size + 14, height: size + 14)
                .background {
                    if isSelected {
                        Circle().fill(tint.color.opacity(colorScheme == .dark ? 0.55 : 0.22))
                    } else if isHovered {
                        Circle().fill(Color.primary.opacity(0.08))
                    }
                }
                .scaleEffect(isHovered ? 1.12 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(ReactionPillButtonStyle())
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityLabel(Text(verbatim: emoji))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if os(macOS)
extension View {
    /// The full emoji picker in a popover anchored to the view. Choosing an
    /// emoji closes it.
    func reactionPickerPopover(
        isPresented: Binding<Bool>,
        selected: Set<String>,
        tint: MessageBubbleColor,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            EmojiPickerView(selected: selected, tint: tint) { emoji in
                isPresented.wrappedValue = false
                onSelect(emoji)
            }
        }
    }
}
#endif

// MARK: - macOS quick bar

#if os(macOS)
/// The bar that floats beside a hovered message: a Liquid Glass capsule
/// with the quick reactions, my current ones marked, and a "+" that opens
/// the full emoji picker. Where there is no room for it beside the bubble,
/// a single add button stands in and opens the picker, so the bar never
/// covers message text.
struct ReactionQuickBar: View {
    let selected: Set<String>
    let tint: MessageBubbleColor
    /// True while the picker popover is open; the list keeps the bar for it.
    @Binding var isPresentingChoices: Bool
    let onSelect: (String) -> Void

    @State private var isHoveringMore = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ReactionChoicesRow(selected: selected, tint: tint, emojiSize: 18, onSelect: onSelect)
                Button {
                    isPresentingChoices = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(isHoveringMore ? 0.1 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringMore = $0 }
                .help(String(localized: "content.reaction.add", comment: "Menu item or title for adding a reaction to a message"))
                .accessibilityLabel(String(localized: "content.reaction.add", comment: "Menu item or title for adding a reaction to a message"))
                .reactionPickerPopover(isPresented: $isPresentingChoices, selected: selected, tint: tint, onSelect: onSelect)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .reactionGlassSurface(in: Capsule(), interactive: true)
            .fixedSize()
            Button {
                isPresentingChoices = true
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .reactionGlassSurface(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "content.accessibility.add_reaction", comment: "Accessibility label for opening the emoji reaction picker"))
            .accessibilityLabel(String(localized: "content.accessibility.add_reaction", comment: "Accessibility label for opening the emoji reaction picker"))
            .reactionPickerPopover(isPresented: $isPresentingChoices, selected: selected, tint: tint, onSelect: onSelect)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

/// Lays out a message row with its quick bar: the message on its side of
/// the row, as the row frame would place it, and the bar in the free space
/// beside the bubble, centered on it. The bar takes no part in the row's
/// size, so showing it moves nothing.
struct ReactionQuickBarLayout: Layout {
    /// Where the message sits in the row: leading for other people's,
    /// trailing for mine, centered for system lines.
    let alignment: HorizontalAlignment
    var gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let isSelf = alignment == .trailing
        let contentX: CGFloat
        switch alignment {
        case .trailing: contentX = bounds.maxX - size.width
        case .center: contentX = bounds.midX - size.width / 2
        default: contentX = bounds.minX
        }
        content.place(at: CGPoint(x: contentX, y: bounds.minY), proposal: ProposedViewSize(size))

        guard subviews.count > 1, alignment != .center else { return }
        let bar = subviews[1]
        let room = max(0, bounds.width - size.width - gap)
        let barSize = bar.sizeThatFits(ProposedViewSize(width: room, height: nil))
        // Centered on the bubble, which ends where the row's bubble-bottom
        // guide says (the pills below do not count).
        let bubbleBottom = content.dimensions(in: ProposedViewSize(size))[.messageBubbleBottom]
        let centerY = bounds.minY + min(bubbleBottom, size.height) / 2
        let barX = isSelf ? contentX - gap - barSize.width : contentX + size.width + gap
        bar.place(
            at: CGPoint(x: barX, y: centerY - barSize.height / 2),
            proposal: ProposedViewSize(width: min(room, barSize.width), height: barSize.height)
        )
    }
}

extension View {
    /// Hosts the quick bar beside the message (see
    /// `ReactionQuickBarLayout`). The row fills its width.
    func reactionQuickBar<Bar: View>(
        alignment: HorizontalAlignment,
        isShown: Bool,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        ReactionQuickBarLayout(alignment: alignment) {
            self
            if isShown {
                bar()
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.85), value: isShown)
    }
}
#endif

// MARK: - Context menu

/// The reaction row at the top of a message's context menu. From iOS 17
/// (and on macOS) it is a palette, the native row of round choices closest
/// to the Messages tapback row; my current reactions are marked, and a
/// last "+" opens the full emoji picker. Before iOS 17 it is a control
/// group.
struct ReactionMenuRow: View {
    let selected: Set<String>
    let tint: MessageBubbleColor
    let onSelect: (String) -> Void
    let onOpenPicker: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            palette
        } else {
            ControlGroup {
                ForEach(MessageReaction.emojis.prefix(3), id: \.self) { emoji in
                    Button(emoji) { onSelect(emoji) }
                }
            }
            Button(action: onOpenPicker) {
                Label(String(localized: "content.reaction.add", comment: "Menu item or title for adding a reaction to a message"), systemImage: "face.smiling")
            }
        }
        #else
        palette
        #endif
    }

    @available(iOS 17.0, macOS 14.0, *)
    private var palette: some View {
        ControlGroup {
            ForEach(MessageReaction.emojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Label {
                        Text(verbatim: emoji)
                    } icon: {
                        EmojiMenuImage.image(for: emoji, isSelected: selected.contains(emoji), tint: tint, colorScheme: colorScheme)
                    }
                }
            }
            Button(action: onOpenPicker) {
                Label(String(localized: "content.reaction.add", comment: "Menu item or title for adding a reaction to a message"), systemImage: "plus")
            }
        }
        .controlGroupStyle(.palette)
    }
}

/// Emoji drawn into an image, the only label a menu palette shows; drawn
/// in its own colors so the menu does not tint it, on a soft disc of the
/// message color when it is one of my reactions.
enum EmojiMenuImage {
    static func image(for emoji: String, isSelected: Bool, tint: MessageBubbleColor, colorScheme: ColorScheme) -> Image {
        let side: CGFloat = 30
        let fontSize: CGFloat = 21
        let rgb = tint.rgb
        let discAlpha: CGFloat = colorScheme == .dark ? 0.6 : 0.28
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { _ in
            if isSelected {
                UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: discAlpha)
                    .setFill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            }
            draw(emoji, fontSize: fontSize, side: side, font: UIFont.systemFont(ofSize: fontSize))
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
        #else
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            if isSelected {
                NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: discAlpha).setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            draw(emoji, fontSize: fontSize, side: side, font: NSFont.systemFont(ofSize: fontSize))
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image).renderingMode(.original)
        #endif
    }

    #if os(iOS)
    private static func draw(_ emoji: String, fontSize: CGFloat, side: CGFloat, font: UIFont) {
        var text = NSAttributedString(string: emoji, attributes: [.font: font])
        // A wide emoji (or one drawn as several glyphs) shrinks to fit.
        let width = text.size().width
        if width > side - 2 {
            text = NSAttributedString(string: emoji, attributes: [.font: font.withSize(fontSize * (side - 2) / width)])
        }
        let size = text.size()
        text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
    }
    #else
    private static func draw(_ emoji: String, fontSize: CGFloat, side: CGFloat, font: NSFont) {
        var text = NSAttributedString(string: emoji, attributes: [.font: font])
        // A wide emoji (or one drawn as several glyphs) shrinks to fit.
        let width = text.size().width
        if width > side - 2 {
            text = NSAttributedString(string: emoji, attributes: [.font: font.withSize(fontSize * (side - 2) / width)])
        }
        let size = text.size()
        text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
    }
    #endif
}

// MARK: - Flow layout

/// Wraps pills into rows, each row lined up with `alignment`'s edge.
struct ReactionFlowLayout: Layout {
    var spacing: CGFloat
    var alignment: HorizontalAlignment = .leading
    /// Rows wrap at this width even when offered more, and the layout is
    /// only as wide as its widest row.
    var maxWidth: CGFloat = .infinity

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: min(proposal.width ?? .infinity, maxWidth))
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: min(bounds.width, maxWidth)) {
            var x = alignment == .trailing ? bounds.maxX - row.width : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Pills of one row share a center line.
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width limit: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > limit {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
