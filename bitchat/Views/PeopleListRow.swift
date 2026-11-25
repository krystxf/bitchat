//
// PeopleListRow.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The standard row of the sidebar's people and groups: a leading icon (an
/// avatar or a glyph), a title with an optional detail line under it, and
/// trailing accessories (unread, favorite).
///
/// Text uses the hierarchical `.primary`/`.secondary` styles, not concrete
/// colors, so a selected sidebar row switches it to the highlight's text
/// color.
struct PeopleRow<Icon: View, Title: View, Accessories: View>: View {
    let subtitle: String?
    let icon: Icon
    let title: Title
    let accessories: Accessories

    init(
        subtitle: String? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title,
        @ViewBuilder accessories: () -> Accessories
    ) {
        self.subtitle = subtitle
        self.icon = icon()
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
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                icon
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
        subtitle: String? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title
    ) {
        self.init(subtitle: subtitle, icon: icon, title: title, accessories: { EmptyView() })
    }
}

/// A tinted SF Symbol as a row's leading icon.
struct PeopleRowGlyph: View {
    /// One column width for every glyph, so names line up even though the
    /// glyphs differ in width. Scales with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 28

    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .foregroundColor(color)
            .frame(width: width)
    }
}

/// A person's name with the disambiguating "#abcd" suffix dimmed, so two
/// people with one nickname stay apart without the suffix shouting.
struct PeopleRowName: View {
    let name: String

    var body: some View {
        let (base, suffix) = name.splitSuffix()
        HStack(spacing: 0) {
            Text(verbatim: base)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !suffix.isEmpty {
                Text(verbatim: suffix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Trailing unread marker, shared by every row that opens a chat.
struct PeopleUnreadIndicator: View {
    private static let tooltip = String(localized: "mesh_peers.tooltip.new_messages", comment: "Tooltip for the unread messages indicator")

    var body: some View {
        Image(systemName: "envelope.fill")
            .foregroundColor(.orange)
            .help(Self.tooltip)
    }
}

/// The only row of the sidebar's people when there is nobody to list.
struct PeopleEmptyRow: View {
    var body: some View {
        Text("geohash_people.none_nearby")
            .foregroundStyle(.secondary)
    }
}
