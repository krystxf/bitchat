//
// InitialsAvatar.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// A rounded-square tile with someone's initials, in their color on a tint
/// of it. `AvatarIdentity` picks the color and the initials, so a person
/// looks the same wherever they show up.
///
/// Decorative: VoiceOver skips it, because the person's name always sits
/// near it.
struct InitialsAvatar: View {
    static let defaultSize: CGFloat = 28

    let name: String
    /// What picks the color (`AvatarIdentity.seed(for:nickname:)`).
    let seed: String
    var size: CGFloat = defaultSize

    var body: some View {
        // Runs only when the name, seed or size change: SwiftUI skips the
        // body of an unchanged view.
        let initials = AvatarIdentity.initials(for: name)
        AvatarTile(seed: seed) { ink in
            Text(verbatim: initials)
                // A fixed size: the tile does not grow with Dynamic Type,
                // so its initials must not either.
                .font(.system(size: size * (initials.count > 1 ? 0.38 : 0.45), weight: .bold, design: .rounded))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(size * 0.1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension InitialsAvatar {
    /// The avatar of the person behind `peerID`, or of the nickname when
    /// there is no peer ID.
    init(name: String, peerID: PeerID?, size: CGFloat = defaultSize) {
        self.init(name: name, seed: AvatarIdentity.seed(for: peerID, nickname: name), size: size)
    }
}

/// The outline of every avatar: a square with continuous rounded corners.
/// Use it for anything drawn around an avatar, such as a selection ring.
struct AvatarShape: InsettableShape {
    /// Corner radius as a share of the side.
    static let cornerFraction: CGFloat = 0.32

    private var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        // The radius follows the full tile, so an inset outline stays
        // parallel to the tile's edge.
        let radius = min(rect.width, rect.height) * Self.cornerFraction - insetAmount
        return RoundedRectangle(cornerRadius: max(0, radius), style: .continuous)
            .path(in: rect.insetBy(dx: insetAmount, dy: insetAmount))
    }

    func inset(by amount: CGFloat) -> AvatarShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// The tile behind an avatar's initials or glyph: `AvatarShape` filled with
/// a tint of the color `AvatarIdentity` picks for `seed`. The content gets
/// the matching ink (`AvatarIdentity.tile(for:isDark:)`).
struct AvatarTile<Content: View>: View {
    let seed: String
    @ViewBuilder let content: (Color) -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tile = AvatarIdentity.tile(
            for: AvatarIdentity.color(forSeed: seed),
            isDark: colorScheme == .dark
        )
        AvatarShape()
            .fill(Color(avatarRGB: tile.fill))
            .overlay(content(Color(avatarRGB: tile.ink)))
    }
}

/// A disc in the color `AvatarIdentity` picks for `seed`, with a soft shade
/// toward the bottom. The shade only darkens, so white content on top
/// keeps its contrast. The mesh map draws its nodes with it.
struct AvatarDisc: View {
    let seed: String

    var body: some View {
        Circle()
            .fill(Color(avatarRGB: AvatarIdentity.color(forSeed: seed)))
            .overlay(
                Circle().fill(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
    }
}

extension Color {
    init(avatarRGB rgb: AvatarIdentity.RGB) {
        self.init(
            .sRGB,
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255,
            opacity: 1
        )
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        ForEach(["Alice Smith", "anon9214#a1b2", "bob", "🔥 blaze", "王小明", ""], id: \.self) { name in
            HStack {
                InitialsAvatar(name: name, peerID: nil, size: 40)
                Text(verbatim: name)
            }
        }
    }
    .padding()
    .background(Color.novaBackground)
}
#endif
