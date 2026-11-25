//
// PersonPresence.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// How someone in the sidebar can be reached right now. The badge on their
/// avatar shows it.
///
/// Each state has its own glyph, so the badge does not depend on color
/// alone. The glyphs are the ones the symbols legend in settings explains.
enum PersonPresence: CaseIterable, Equatable {
    /// In Bluetooth range.
    case meshConnected
    /// Out of radio range, but other mesh peers relay to them.
    case meshRelayed
    /// Off the mesh, but a mutual favorite: Nostr carries the messages.
    case nostr
    /// Not reachable now.
    case offline
    /// In the location channel, and physically in its area.
    case nearby
    /// In the location channel, but joined it from elsewhere.
    case teleported
    /// Across the mesh bridge: in the same area, beyond radio range.
    case bridged

    /// The SF Symbol inside the badge.
    var systemImage: String {
        switch self {
        case .meshConnected: "antenna.radiowaves.left.and.right"
        case .meshRelayed: "point.3.filled.connected.trianglepath.dotted"
        case .nostr: "globe"
        case .offline: "antenna.radiowaves.left.and.right.slash"
        case .nearby: "mappin"
        case .teleported: "face.dashed"
        case .bridged: "network"
        }
    }

    /// The badge's fill. Each is dark enough for its white glyph at WCAG AA
    /// (4.5:1); `PersonPresenceTests` checks it. Green means in the room
    /// now (radio, relay or the area), purple means over Nostr.
    var badgeColor: AvatarIdentity.RGB {
        switch self {
        case .meshConnected, .meshRelayed, .nearby: AvatarIdentity.RGB(hex: 0x15803D) // green
        case .nostr: AvatarIdentity.RGB(hex: 0x7E22CE) // purple
        case .offline: AvatarIdentity.RGB(hex: 0x6B7280) // gray
        case .teleported: AvatarIdentity.RGB(hex: 0x0F766E) // teal
        case .bridged: AvatarIdentity.RGB(hex: 0x0E7490) // cyan
        }
    }

    /// What the badge says, for VoiceOver and the tooltip.
    var label: String {
        switch self {
        case .meshConnected:
            String(localized: "content.accessibility.connected_mesh", comment: "Accessibility label for mesh-connected peer indicator")
        case .meshRelayed:
            String(localized: "content.accessibility.reachable_mesh", comment: "Accessibility label for mesh-reachable peer indicator")
        case .nostr:
            String(localized: "content.accessibility.available_nostr", comment: "Accessibility label for Nostr-available peer indicator")
        case .offline:
            String(localized: "mesh_peers.state.offline", comment: "State label for a peer that is not currently reachable")
        case .nearby:
            String(localized: "geohash_people.state.nearby", comment: "State label for someone physically in the location channel's area")
        case .teleported:
            String(localized: "geohash_people.state.teleported", comment: "State label for someone who joined the location channel from elsewhere")
        case .bridged:
            String(localized: "bridge_people.section_title", defaultValue: "across the bridge", comment: "Section header in the people sheet for participants reachable via the mesh bridge")
        }
    }
}

extension MeshPeerRow {
    /// The best route first: radio, then relay, then Nostr.
    var presence: PersonPresence {
        if isConnected { return .meshConnected }
        if isReachable { return .meshRelayed }
        if isMutualFavorite { return .nostr }
        return .offline
    }
}

extension GeohashPersonRow {
    var presence: PersonPresence {
        isTeleported ? .teleported : .nearby
    }
}
