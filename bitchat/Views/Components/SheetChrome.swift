//
// SheetChrome.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A grouped Form in Nova's colors, for settings-like screens: the warm
/// backdrop, cream rows with warm separators, and the blue accent on
/// switches and buttons.
struct NovaForm<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form {
            Group {
                content
            }
            .novaRows()
        }
        .formStyle(.grouped)
        .novaGroupedList()
    }
}

extension View {
    /// Gives the rows of a grouped Form or List Nova's surface and
    /// hairlines. Apply it to the rows or sections, inside the list. A row
    /// that sets its own `listRowBackground` keeps it.
    func novaRows() -> some View {
        listRowBackground(Color.novaSurface)
            .listRowSeparatorTint(.novaHairline)
    }

    /// A grouped Form or List on Nova's backdrop, with the blue accent on
    /// switches (the system default is green). Apply it to the list.
    func novaGroupedList() -> some View {
        novaListBackground()
            .tint(.novaAccent)
    }

    /// A section footer's or header's text in Nova's warm secondary color.
    func novaSectionText() -> some View {
        foregroundStyle(.novaSecondaryText)
    }
}

extension View {
    /// The top bar of a sheet, the same on iOS and macOS: the title (and an
    /// optional subtitle) at the top, the sheet's actions beside it, and a
    /// Liquid Glass close "X" in the top-trailing corner. Apply it to the
    /// sheet's root content, outside any `NavigationStack`: it adds the
    /// stack itself where the platform needs one.
    ///
    ///     content.sheetChrome(title: Text("notices"), onClose: { dismiss() }) {
    ///         Button(action: refresh) {
    ///             Label("refresh", systemImage: "arrow.clockwise")
    ///         }
    ///     }
    ///
    /// - iOS: a `NavigationStack` with an inline navigation bar. Leading
    ///   items sit on the leading edge; trailing items and the close role
    ///   button sit on the trailing edge. iOS 26 draws them as glass.
    /// - macOS: a sheet's native toolbar moves modal actions into a bottom
    ///   button bar and drops leading, trailing and principal items. So
    ///   macOS gets a top bar of its own, with glass circle buttons and the
    ///   title centered between them, as on iOS. Escape closes the sheet.
    ///
    /// Pass buttons with a `Label` (icon plus text). The bar shows the icon
    /// only and keeps the text for VoiceOver.
    ///
    /// - Parameters:
    ///   - title: The sheet title.
    ///   - subtitle: A secondary line under the title.
    ///   - closeLabel: The close button's accessibility label, when the
    ///     sheet needs a more specific one than "close".
    ///   - onClose: Closes the sheet.
    ///   - principal: A control that replaces the title on screen, such as
    ///     a segmented picker. On iOS the title still names the screen for
    ///     VoiceOver.
    ///   - leading: Buttons for the leading edge, such as "back".
    ///   - trailing: Action buttons, placed before the close button.
    func sheetChrome<Principal: View, Leading: View, Trailing: View>(
        title: Text,
        subtitle: Text? = nil,
        closeLabel: Text? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder principal: () -> Principal = { EmptyView() },
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(SheetChrome(
            title: title,
            subtitle: subtitle,
            closeLabel: closeLabel,
            onClose: onClose,
            principal: principal(),
            leading: leading(),
            trailing: trailing()
        ))
    }
}

private struct SheetChrome<Principal: View, Leading: View, Trailing: View>: ViewModifier {
    let title: Text
    let subtitle: Text?
    let closeLabel: Text?
    let onClose: () -> Void
    let principal: Principal
    let leading: Leading
    let trailing: Trailing

    private var hasPrincipal: Bool { Principal.self != EmptyView.self }
    private var hasLeading: Bool { Leading.self != EmptyView.self }
    private var hasTrailing: Bool { Trailing.self != EmptyView.self }

    func body(content: Content) -> some View {
        #if os(iOS)
        NavigationStack {
            content
                // Nova's backdrop for every sheet; a Form or List in it
                // shows the same color (`novaGroupedList()`).
                .background(Color.novaBackground.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SheetNavigationSubtitle(subtitle: subtitle))
                .toolbar { toolbarContent }
        }
        #else
        content
            .background(Color.novaBackground.ignoresSafeArea())
            .safeAreaBar(edge: .top, spacing: 0) {
                SheetTopBar(spacing: 12) {
                    HStack(spacing: 8) {
                        leading
                    }
                    centerContent
                    HStack(spacing: 8) {
                        trailing
                        SheetCloseButton(label: closeLabel, action: onClose)
                    }
                }
                .labelStyle(SheetBarIconLabelStyle())
                .glassButtonStyle()
                .circularButtonShape()
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
        #endif
    }

    #if os(iOS)
    /// iOS before 26 has no navigation subtitle, so a sheet with one shows
    /// the title over the subtitle in the title slot.
    private var needsSubtitleFallback: Bool {
        guard subtitle != nil else { return false }
        if #available(iOS 26.0, *) { return false }
        return true
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if hasLeading {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                leading
            }
        }
        if hasPrincipal {
            ToolbarItem(placement: .principal) {
                principal
            }
        } else if needsSubtitleFallback, let subtitle {
            ToolbarItem(placement: .principal) {
                SheetTitleView(title: title, subtitle: subtitle)
            }
        }
        if hasTrailing {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                trailing
            }
            // Gives the close button a glass circle of its own instead of
            // sharing the actions' capsule.
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            SheetCloseButton(label: closeLabel, action: onClose)
        }
    }
    #else
    @ViewBuilder
    private var centerContent: some View {
        if hasPrincipal {
            principal
        } else {
            SheetTitleView(title: title, subtitle: subtitle)
        }
    }
    #endif
}

/// The close "X". On iOS 26 the system close role, which a navigation bar
/// draws as glass; before 26 a text button. On macOS a glass circle (the
/// top bar supplies the style), like the image viewer's close button.
private struct SheetCloseButton: View {
    let label: Text?
    let action: () -> Void

    private var defaultLabel: Text {
        Text("common.close", comment: "Accessibility label for close buttons")
    }

    var body: some View {
        closeButton
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(label ?? defaultLabel)
    }

    @ViewBuilder
    private var closeButton: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action)
        } else {
            Button(action: action) {
                defaultLabel
            }
        }
        #else
        Button(action: action) {
            Label {
                defaultLabel
            } icon: {
                Image(systemName: "xmark")
            }
        }
        .help(defaultLabel)
        #endif
    }
}

/// The title, with the subtitle under it when there is one, sized like the
/// system's inline navigation title.
private struct SheetTitleView: View {
    let title: Text
    let subtitle: Text?

    var body: some View {
        VStack(spacing: 1) {
            title
                .font(.headline)
                // Middle truncation keeps both ends of a long name visible.
                .truncationMode(.middle)
            if let subtitle {
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#if os(iOS)
/// `.navigationSubtitle` exists on iOS from 26.
private struct SheetNavigationSubtitle: ViewModifier {
    let subtitle: Text?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}
#endif

#if os(macOS)
/// A bar button's icon in a fixed square, so every glass circle in the top
/// bar has the same size whatever the symbol's width. The label's text
/// stays for VoiceOver and tooltips.
private struct SheetBarIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 24, height: 24)
    }
}

/// Lays out a navigation bar: the leading group at the leading edge, the
/// trailing group at the trailing edge and the middle view centered on the
/// bar. The middle view gets the width that stays clear of the wider
/// group on both sides, so it is centered even when the sides differ.
private struct SheetTopBar: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)
        let middleWidth = proposal.width.map { middleWidthLimit(in: $0, leading: leading, trailing: trailing) }
        let middle = subviews[1].sizeThatFits(ProposedViewSize(width: middleWidth, height: nil))
        let side = max(leading.width, trailing.width)
        return CGSize(
            width: proposal.width ?? (middle.width + 2 * (side + spacing)),
            height: max(leading.height, middle.height, trailing.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)
        let middleWidth = middleWidthLimit(in: bounds.width, leading: leading, trailing: trailing)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: .unspecified
        )
        subviews[1].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: middleWidth, height: nil)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: .unspecified
        )
    }

    private func middleWidthLimit(in width: CGFloat, leading: CGSize, trailing: CGSize) -> CGFloat {
        max(0, width - 2 * (max(leading.width, trailing.width) + spacing))
    }
}
#endif
