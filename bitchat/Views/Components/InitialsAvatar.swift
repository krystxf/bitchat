//
// InitialsAvatar.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// A circle with someone's initials in white on their color, as Messages
/// shows beside other people's bubbles. `AvatarIdentity` picks both, so a
/// person looks the same wherever they show up.
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
        Circle()
            .fill(Color(avatarRGB: AvatarIdentity.color(forSeed: seed)))
            // A soft shade toward the bottom, as on Messages' avatars. It
            // only darkens, so the initials keep their contrast.
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
                Text(verbatim: initials)
                    // A fixed size: the circle does not grow with Dynamic
                    // Type, so its initials must not either.
                    .font(.system(size: size * (initials.count > 1 ? 0.38 : 0.45), weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.1)
            )
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

private extension Color {
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
                InitialsAvatar(name: name, peerID: nil)
                Text(verbatim: name)
            }
        }
    }
    .padding()
}
#endif
