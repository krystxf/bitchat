//
// GroupAvatar.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// A private group's avatar: the group glyph on the group's own tile.
/// `AvatarIdentity` picks the color from the group ID, as it does for a
/// person, so a group keeps its color when it is renamed.
///
/// A glyph, not initials, so a group never looks like a person.
///
/// Decorative: VoiceOver skips it, because the group's name always sits
/// near it.
struct GroupAvatar: View {
    let groupID: PeerID
    var size: CGFloat = InitialsAvatar.defaultSize

    var body: some View {
        AvatarTile(seed: AvatarIdentity.seed(for: groupID, nickname: "")) { ink in
            Image(systemName: "person.3.fill")
                .resizable()
                .scaledToFit()
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(ink)
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 12) {
        ForEach(0..<4, id: \.self) { index in
            GroupAvatar(groupID: PeerID(groupID: Data([UInt8(index)])), size: 36)
        }
    }
    .padding()
    .background(Color.novaBackground)
}
#endif
