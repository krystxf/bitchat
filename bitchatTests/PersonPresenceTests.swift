//
// PersonPresenceTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

struct PersonPresenceTests {
    // MARK: - Mesh peers

    @Test func aPeerInRadioRangeIsConnected() {
        #expect(meshPeer(isConnected: true, isReachable: true, isMutualFavorite: true).presence == .meshConnected)
    }

    @Test func aPeerOnlyOtherPeersReachIsRelayed() {
        #expect(meshPeer(isReachable: true, isMutualFavorite: true).presence == .meshRelayed)
    }

    @Test func aMutualFavoriteOffTheMeshIsOnNostr() {
        #expect(meshPeer(isMutualFavorite: true).presence == .nostr)
    }

    @Test func anyoneElseIsOffline() {
        #expect(meshPeer().presence == .offline)
    }

    // MARK: - Location channel people

    @Test func aPersonInTheAreaIsNearby() {
        #expect(geohashPerson(isTeleported: false).presence == .nearby)
    }

    @Test func aPersonFromElsewhereIsTeleported() {
        #expect(geohashPerson(isTeleported: true).presence == .teleported)
    }

    // MARK: - Badge

    /// The glyph tells the states apart, so the badge does not depend on
    /// color alone.
    @Test func everyStateHasItsOwnGlyph() {
        let glyphs = PersonPresence.allCases.map(\.systemImage)
        #expect(Set(glyphs).count == glyphs.count)
    }

    @Test func everyStateHasALabel() {
        for presence in PersonPresence.allCases {
            #expect(!presence.label.isEmpty, "\(presence) has no label")
        }
    }

    @Test func whiteGlyphsMeetWCAGAAOnEveryBadge() {
        for presence in PersonPresence.allCases {
            let ratio = contrastRatio(luminance(of: presence.badgeColor), 1.0)
            #expect(ratio >= 4.5, "white on the \(presence) badge is \(ratio):1")
        }
    }

    // MARK: - Helpers

    private func meshPeer(
        isConnected: Bool = false,
        isReachable: Bool = false,
        isMutualFavorite: Bool = false
    ) -> MeshPeerRow {
        MeshPeerRow(
            peerID: PeerID(str: "00000000000000a1"),
            displayName: "alice",
            isMe: false,
            hasUnread: false,
            isBlocked: false,
            isFavorite: isMutualFavorite,
            isConnected: isConnected,
            isReachable: isReachable,
            isMutualFavorite: isMutualFavorite,
            encryptionStatus: .noHandshake,
            showsVerifiedBadgeWhenOffline: false,
            showsVouchedBadge: false,
            isVerified: false,
            hasAcceptedConversation: false
        )
    }

    private func geohashPerson(isTeleported: Bool) -> GeohashPersonRow {
        GeohashPersonRow(
            id: "ab",
            displayName: "bob",
            isMe: false,
            isTeleported: isTeleported,
            isBlocked: false,
            hasAcceptedConversation: false
        )
    }

    /// WCAG 2 relative luminance.
    private func luminance(of color: AvatarIdentity.RGB) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private func contrastRatio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
