//
// PeopleListRow.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The standard row of the sidebar's people and groups: a leading avatar, a
/// title with an optional detail line under it, and trailing accessories
/// (state icons, then the unread dot at the very end).
///
/// Detail text takes Nova's warm secondary color, and the highlight's own
/// text colors on a selected row (`rowColor(_:)`).
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
                            .rowColor(.secondary)
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
            .font(.footnote)
            .imageScale(.medium)
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

/// A person's name with the disambiguating "#abcd" suffix dimmed, so two
/// people with one nickname stay apart without the suffix shouting. A
/// verified or vouched-for person gets a seal right after the name, as a
/// verified account does in other apps.
struct PeopleRowName: View {
    let name: String
    var seal: PeopleRowSeal? = nil

    var body: some View {
        let (base, suffix) = name.splitSuffix()
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(verbatim: base)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !suffix.isEmpty {
                    Text(verbatim: suffix)
                        .rowColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let seal {
                PeopleRowSealImage(seal: seal)
                    .font(.footnote)
                    .imageScale(.medium)
                    .fixedSize()
            }
        }
    }
}

/// The seal after a person's name. Verified (the filled seal, in the
/// accent color) means the user checked the person's fingerprint; vouched
/// (the outline seal) means someone the user verified did.
///
/// Decorative: the row's accessibility label says the state.
enum PeopleRowSeal {
    case verified
    case vouched
}

private struct PeopleRowSealImage: View {
    let seal: PeopleRowSeal

    private enum Strings {
        static let verified = String(localized: "app_info.legend.verified", comment: "Legend entry for the verified seal glyph")
        static let vouched = String(localized: "mesh_peers.tooltip.vouched", comment: "Tooltip for the vouched (unfilled seal) badge next to a peer")
    }

    var body: some View {
        switch seal {
        case .verified:
            Image(systemName: "checkmark.seal.fill")
                .rowColor(.accent)
                .help(Strings.verified)
                .accessibilityHidden(true)
        case .vouched:
            Image(systemName: "checkmark.seal")
                .rowColor(.secondary)
                .help(Strings.vouched)
                .accessibilityHidden(true)
        }
    }
}

/// Trailing unread marker, shared by every row that opens a chat: a dot in
/// the accent color, as Messages and Mail mark unread conversations. Not
/// the gold highlight: that is the favorite star's, right beside it.
struct PeopleUnreadIndicator: View {
    private static let tooltip = String(localized: "mesh_peers.tooltip.new_messages", comment: "Tooltip for the unread messages indicator")

    @ScaledMetric(relativeTo: .footnote) private var diameter: CGFloat = 10

    var body: some View {
        Circle()
            .rowColor(.accent)
            .frame(width: diameter, height: diameter)
            .help(Self.tooltip)
            .accessibilityHidden(true)
    }
}

/// A Nova palette color on a row, and the row's own text color while it is
/// selected, so the mark or text stays visible on the accent highlight.
struct RowColorStyle: ViewModifier {
    enum Role {
        /// The accent: the verified seal and the unread dot.
        case accent
        /// The gold highlight: the favorite star.
        case highlight
        /// Detail text and dimmed glyphs.
        case secondary
    }

    let role: Role

    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, *) {
            content.modifier(ProminenceAwareRowColor(role: role))
        } else {
            content.foregroundStyle(role.color)
        }
    }
}

private extension RowColorStyle.Role {
    var color: Color {
        switch self {
        case .accent: .novaAccent
        case .highlight: .novaHighlight
        case .secondary: .novaSecondaryText
        }
    }
}

@available(iOS 17, macOS 14, *)
private struct ProminenceAwareRowColor: ViewModifier {
    let role: RowColorStyle.Role

    @Environment(\.backgroundProminence) private var prominence

    func body(content: Content) -> some View {
        if prominence == .increased {
            // The selection highlight's own text colors.
            if role == .secondary {
                content.foregroundStyle(.secondary)
            } else {
                content.foregroundStyle(.primary)
            }
        } else {
            content.foregroundStyle(role.color)
        }
    }
}

extension View {
    /// Colors a row's text or mark with a Nova palette role; see
    /// `RowColorStyle`.
    func rowColor(_ role: RowColorStyle.Role) -> some View {
        modifier(RowColorStyle(role: role))
    }
}

/// The only row of a people list when there is nobody to list.
struct PeopleEmptyRow: View {
    var text = Text("geohash_people.none_nearby")

    var body: some View {
        text
            .font(.subheadline)
            .foregroundStyle(.novaSecondaryText)
    }
}
