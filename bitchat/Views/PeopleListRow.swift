//
// PeopleListRow.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The standard row of the people sheet's list: a leading glyph, a title
/// with an optional detail line under it, and trailing accessories (unread,
/// favorite).
///
/// Colors are concrete `Color`s on purpose. Inside a list-row `Button` the
/// hierarchical `.primary`/`.secondary` styles resolve against the button
/// tint, so names would render in the accent color.
struct PeopleRow<Title: View, Accessories: View>: View {
    @ThemedPalette private var palette
    /// One column width for every leading glyph, so names line up even
    /// though the glyphs differ in width. Scales with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    let systemImage: String
    let iconColor: Color
    let subtitle: String?
    let title: Title
    let accessories: Accessories

    init(
        systemImage: String,
        iconColor: Color,
        subtitle: String? = nil,
        @ViewBuilder title: () -> Title,
        @ViewBuilder accessories: () -> Accessories
    ) {
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.subtitle = subtitle
        self.title = title()
        self.accessories = accessories()
    }

    var body: some View {
        HStack(spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.subheadline)
                            .foregroundColor(palette.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundColor(iconColor)
                    .frame(width: iconWidth)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                accessories
            }
            .font(.subheadline)
        }
        // The whole row is the hit target, Spacer included.
        .contentShape(Rectangle())
    }
}

extension PeopleRow where Accessories == EmptyView {
    init(
        systemImage: String,
        iconColor: Color,
        subtitle: String? = nil,
        @ViewBuilder title: () -> Title
    ) {
        self.init(
            systemImage: systemImage,
            iconColor: iconColor,
            subtitle: subtitle,
            title: title,
            accessories: { EmptyView() }
        )
    }
}

/// A person's name with the disambiguating "#abcd" suffix dimmed, so two
/// people with one nickname stay apart without the suffix shouting.
struct PeopleRowName: View {
    @ThemedPalette private var palette

    let name: String
    var isEmphasized = false

    var body: some View {
        let (base, suffix) = name.splitSuffix()
        HStack(spacing: 0) {
            Text(verbatim: base)
                .fontWeight(isEmphasized ? .semibold : .regular)
                .foregroundColor(palette.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !suffix.isEmpty {
                Text(verbatim: suffix)
                    .foregroundColor(palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Trailing unread marker, shared by every tappable section.
struct PeopleUnreadIndicator: View {
    private static let tooltip = String(localized: "mesh_peers.tooltip.new_messages", comment: "Tooltip for the unread messages indicator")

    var body: some View {
        Image(systemName: "envelope.fill")
            .foregroundColor(.orange)
            .help(Self.tooltip)
    }
}

/// The only row of a roster section with nobody in it.
struct PeopleEmptyRow: View {
    @ThemedPalette private var palette

    var body: some View {
        Text("geohash_people.none_nearby")
            .foregroundColor(palette.secondary)
    }
}

extension View {
    /// The people sheet's list style: inset grouped on iOS, inset on macOS.
    func peopleListStyle() -> some View {
        #if os(macOS)
        return listStyle(.inset)
        #else
        return listStyle(.insetGrouped)
        #endif
    }

    /// A tappable people row. In an iOS list a default-style button gets
    /// the native row highlight. On macOS the default style draws a bordered
    /// push button around the whole row, so the row uses the plain style.
    func peopleRowButtonStyle() -> some View {
        #if os(macOS)
        return buttonStyle(.plain)
        #else
        return self
        #endif
    }
}
