//
// SidebarAvatar.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// A person's avatar at the start of a sidebar row, as Messages shows one
/// in its conversation list. It is the same `InitialsAvatar` as beside
/// their chat bubbles, so a person has one look everywhere.
///
/// An optional badge on the bottom-trailing corner tells how they can be
/// reached. Decorative: VoiceOver skips it, because the row's label says
/// the name and the state.
struct SidebarPersonAvatar: View {
    let name: String
    let peerID: PeerID?
    var presence: PersonPresence?

    var body: some View {
        SidebarAvatar(presence: presence) { size in
            InitialsAvatar(name: name, peerID: peerID, size: size)
        }
    }
}

/// The frame every sidebar avatar (people and groups) shares: its size for
/// the platform, the presence badge, and an outline that keeps it clear of
/// the selection highlight.
struct SidebarAvatar<Avatar: View>: View {
    #if os(macOS)
    @Environment(\.sidebarRowSize) private var rowSize
    #else
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 36
    #endif

    let presence: PersonPresence?
    let avatar: (CGFloat) -> Avatar

    init(presence: PersonPresence? = nil, @ViewBuilder avatar: @escaping (CGFloat) -> Avatar) {
        self.presence = presence
        self.avatar = avatar
    }

    /// Fits the row: macOS follows the sidebar icon size in System
    /// Settings, iOS follows Dynamic Type up to a cap.
    private var size: CGFloat {
        #if os(macOS)
        switch rowSize {
        case .small: 28
        case .large: 36
        default: 32
        }
        #else
        min(scaledSize, 56)
        #endif
    }

    var body: some View {
        let size = self.size
        let badgeSize = (size * 0.42).rounded()
        // The clear ring between the badge and the avatar. A cut-out, not a
        // stroke in the list's color: the selection highlight shows through.
        let gap = max(1.5, (size * 0.05).rounded())

        avatar(size)
            .overlay {
                if #available(iOS 17, macOS 14, *) {
                    SelectedAvatarOutline()
                }
            }
            .mask {
                if presence != nil {
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle()
                        Circle()
                            .frame(width: badgeSize + 2 * gap, height: badgeSize + 2 * gap)
                            .offset(x: gap, y: gap)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                } else {
                    Rectangle()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let presence {
                    PresenceBadge(presence: presence, size: badgeSize)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A white hairline around the avatar on a selected row. The avatar's
/// color can match the selection highlight (blue on blue), and the outline
/// keeps the tile's edge visible.
@available(iOS 17, macOS 14, *)
private struct SelectedAvatarOutline: View {
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        if prominence == .increased {
            AvatarShape()
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        }
    }
}

/// A small disc with the presence glyph in white. The glyph, not only the
/// color, tells the states apart.
struct PresenceBadge: View {
    let presence: PersonPresence
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(avatarRGB: presence.badgeColor))
            .overlay(
                Image(systemName: presence.systemImage)
                    .resizable()
                    .scaledToFit()
                    .font(.system(size: size, weight: .bold))
                    .foregroundColor(.white)
                    .padding(size * 0.2)
            )
            .frame(width: size, height: size)
            .help(presence.label)
    }
}

#if DEBUG
#Preview {
    List {
        ForEach(PersonPresence.allCases, id: \.self) { presence in
            Label {
                Text(verbatim: presence.label)
            } icon: {
                SidebarPersonAvatar(name: "Alice Smith", peerID: nil, presence: presence)
            }
        }
        Label {
            Text(verbatim: "no badge")
        } icon: {
            SidebarPersonAvatar(name: "bob", peerID: nil)
        }
    }
    .listStyle(.sidebar)
}
#endif
