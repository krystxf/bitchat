//
// ConversationInfoPage.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The frame of a conversation info page, as in Messages or Instagram: a
/// large avatar with the name and a status line under it, an optional link
/// under the name, a row of glass quick action buttons, and then the
/// page's own sections. Each kind of conversation fills it in
/// (`GroupInfoPage` and the others); `ConversationInfoPolicy` decides what
/// they offer.
struct ConversationInfoPage<Avatar: View, HeaderAction: View, QuickActions: View, Sections: View>: View {
    let title: Text
    let subtitle: String?
    let avatar: Avatar
    let headerAction: HeaderAction
    let quickActions: QuickActions
    let sections: Sections

    init(
        title: Text,
        subtitle: String?,
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder headerAction: () -> HeaderAction = { EmptyView() },
        @ViewBuilder quickActions: () -> QuickActions = { EmptyView() },
        @ViewBuilder sections: () -> Sections
    ) {
        self.title = title
        self.subtitle = subtitle
        self.avatar = avatar()
        self.headerAction = headerAction()
        self.quickActions = quickActions()
        self.sections = sections()
    }

    var body: some View {
        Form {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            sections
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: Strings.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(spacing: 14) {
            avatar
            VStack(spacing: 4) {
                title
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    // Middle truncation keeps both ends of a long name.
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            headerAction
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
            HStack(alignment: .top, spacing: 10) {
                quickActions
            }
            // Four tiles share one row; past this size their labels have no
            // room left, as on a tab bar.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// An icon-over-label button in the quick action row under the header: a
/// Liquid Glass tile, all tiles one width.
struct ConversationQuickAction: View {
    let title: String
    let systemImage: String
    /// For a toggle (favorite, bookmark): fills the icon and tells
    /// VoiceOver that it is on.
    var isOn = false
    /// What VoiceOver says, when the short title alone is unclear.
    var accessibilityLabel: String?
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .symbolVariant(isOn ? .fill : .none)
                    .frame(height: 24)
                Text(verbatim: title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 4)
        }
        .glassButtonStyle()
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .accessibilityLabel(Text(verbatim: accessibilityLabel ?? title))
        .accessibilityHint(Text(verbatim: accessibilityHint ?? ""))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(accessibilityLabel ?? title)
    }
}

/// A circle with a white SF Symbol on a tint, for a conversation that has
/// no person behind it: a channel or a group. Same shading as
/// `InitialsAvatar`. Decorative: the name sits under it.
struct ConversationGlyphAvatar: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = ConversationInfoMetrics.avatarSize

    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Circle().fill(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                Image(systemName: systemImage)
                    // A fixed size: the circle does not grow with Dynamic
                    // Type, so its glyph must not either.
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum ConversationInfoMetrics {
    /// The header avatar: large on a phone page, smaller in the narrower
    /// macOS inspector.
    static var avatarSize: CGFloat {
        #if os(macOS)
        72
        #else
        88
        #endif
    }
}

/// The conversation's name and status as the title bar's title item, a
/// button that opens the info page. Messages and Instagram open details
/// the same way. It replaces the system title, so apply
/// `conversationTitleBar(hidesNativeTitle:)` with it.
struct ConversationTitleToolbarItem: ToolbarContent {
    let title: Text
    let subtitle: String?
    /// What VoiceOver says instead of the title and subtitle.
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            // It reads as the title, not as one more glass button.
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
        #else
        item
        #endif
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ConversationTitleButton(
                title: title,
                subtitle: subtitle,
                accessibilityLabel: accessibilityLabel,
                action: action
            )
        }
    }
}

extension View {
    /// macOS shows the window title at the start of the detail column's
    /// toolbar. With the title button in the toolbar's center, that title
    /// would show twice, so it goes; the window keeps it for the Window
    /// menu and Mission Control. iOS needs nothing: a principal item
    /// replaces the title.
    @ViewBuilder
    func conversationTitleBar(hidesNativeTitle: Bool) -> some View {
        #if os(macOS)
        if hidesNativeTitle {
            toolbar(removing: .title)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// The conversation's name and status, as a button. A small chevron after
/// the name says that it opens something, as in Messages.
struct ConversationTitleButton: View {
    let title: Text
    let subtitle: String?
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    title
                        .font(.headline)
                        // Middle truncation keeps the identity suffix of a
                        // long nickname visible.
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        // Plain, not the toolbar's default style: that one fixes the item
        // at one line's height and clips the subtitle on macOS.
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .modifier(OptionalAccessibilityLabel(label: accessibilityLabel, value: subtitle))
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint(Text(verbatim: ConversationInfoStrings.openHint))
        .help(ConversationInfoStrings.openHint)
        #if os(macOS)
        // Messages' shortcut for a conversation's details.
        .keyboardShortcut("i", modifiers: .command)
        #endif
    }
}

/// Replaces the combined label with `label`, and moves the subtitle to the
/// value, when there is a label.
private struct OptionalAccessibilityLabel: ViewModifier {
    let label: String?
    let value: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityValue(Text(verbatim: value ?? ""))
        } else {
            content
        }
    }
}

extension View {
    /// Presents a conversation's info page, the most native way on each
    /// platform:
    ///
    /// - iOS pushes it onto the detail column's navigation stack, as
    ///   Messages and Instagram do. The back button returns to the chat.
    /// - macOS shows it in an inspector, a column on the window's trailing
    ///   edge, as Mail and Notes do. The chat stays visible and usable next
    ///   to it, and the title button (or Command-I) hides it again.
    func conversationInfo<Page: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder page: @escaping () -> Page
    ) -> some View {
        modifier(ConversationInfoPresentation(isPresented: isPresented, page: page))
    }
}

private struct ConversationInfoPresentation<Page: View>: ViewModifier {
    @Binding var isPresented: Bool
    let page: () -> Page

    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationDestination(isPresented: $isPresented, destination: page)
        #else
        content.inspector(isPresented: $isPresented) {
            page()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
        }
        #endif
    }
}

enum ConversationInfoStrings {
    static let openHint = String(localized: "conversation_info.accessibility.open_hint", defaultValue: "shows details", comment: "Accessibility hint and tooltip on the conversation title in the title bar, which opens the conversation's details page")

    static func peopleCount(_ count: Int) -> String {
        String(
            format: String(localized: "content.accessibility.people_count", comment: "Accessibility label announcing number of people in header"),
            locale: .current,
            count
        )
    }
}

private enum Strings {
    static let title = String(localized: "conversation_info.title", defaultValue: "details", comment: "Title of the page with a conversation's details: its people, background and actions")
}
