//
// MeshEmptyStateView.swift
// bitchat
//
// The empty mesh timeline, upgraded from a dead end into a live surface:
// a sonar shows the radio scanning, the daily sightings tally proves the
// spot isn't dead, the liveliest nearby geohash conversation is one tap
// away, and notes left at this place surface when there are any.
// This is free and unencumbered software released into the public domain.
//

import Combine
import SwiftUI

struct MeshEmptyStateView: View {
    /// Visible chat height to fill; the radar centers in the space left
    /// below the narration. Zero (previews) keeps a compact layout.
    var fillHeight: CGFloat = 0
    /// Ambient-footer mode, appended below archived echoes: skips the
    /// intro/help narration (the timeline isn't empty) and shrinks the
    /// radar, keeping the sightings tally and the live hints visible.
    var compact: Bool = false
    /// Whether the radio can actually scan. With Bluetooth off or denied the
    /// sweep must not run — an animated "searching" over a dead radio is an
    /// actively false status display. Defaults to true for previews.
    var bluetoothAvailable: Bool = true

    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @ObservedObject private var activityTracker = GeohashChatActivityTracker.shared
    @ObservedObject private var sightingsTracker = MeshSightingsTracker.shared
    @ObservedObject private var nearbyNotes = NearbyNotesCounter.shared

    @ThemedPalette private var palette

    /// The activity window is evaluated at render time; without new events
    /// nothing would trigger a re-render, so a stale "people are talking"
    /// hint could linger. A slow tick keeps the hints and relative times
    /// honest.
    @State private var refreshTick = 0
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum Strings {
        static let meshIntro = String(localized: "content.empty.mesh_intro", comment: "First line of the empty mesh timeline explaining what the mesh channel is")
        static let sightingsOne = String(localized: "content.empty.sightings_one", comment: "Empty mesh timeline stat when exactly one device came within range today")
        static let checkNotes = String(localized: "content.empty.check_notes", comment: "Empty mesh timeline action that starts looking for notes left at this place; before tapping, no lookup runs")

        static func sightingsMany(_ count: Int) -> String {
            String(
                format: String(localized: "content.empty.sightings_many", comment: "Empty mesh timeline stat counting devices that came within range today"),
                locale: .current,
                count
            )
        }

        static func activityOne(_ geohash: String) -> String {
            String(
                format: String(localized: "content.empty.activity_one", comment: "Empty mesh timeline hint when one person is chatting in a nearby geohash channel; placeholder is the geohash"),
                locale: .current,
                geohash
            )
        }

        static func activityMany(_ geohash: String) -> String {
            String(
                format: String(localized: "content.empty.activity_many", comment: "Empty mesh timeline hint when several people are chatting in a nearby geohash channel; placeholder is the geohash"),
                locale: .current,
                geohash
            )
        }

    }

    /// The radar means "searching for people": once anyone is connected or
    /// reachable on the mesh, the search is over and the sweep goes away.
    /// And it only means that while the radio is actually on — the
    /// connectivity banner carries the message when it isn't.
    private var isSearchingForPeers: Bool {
        bluetoothAvailable
            && peerListModel.connectedMeshPeerCount == 0
            && peerListModel.reachableMeshPeerCount == 0
    }

    var body: some View {
        VStack(spacing: 16) {
            if compact {
                if isSearchingForPeers {
                    radarBlock
                }
                actions
            } else {
                Spacer(minLength: 24)
                ChatEmptyStateHeader(
                    title: "#mesh",
                    message: Strings.meshIntro
                ) {
                    if isSearchingForPeers {
                        radarBlock
                    } else {
                        ChatEmptyStateSymbol(systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                actions
                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: compact ? 0 : fillHeight)
        .onReceive(refreshTimer) { _ in
            refreshTick += 1
            // Roll the tally over if the local day changed while idle.
            sightingsTracker.refreshForDisplay()
        }
    }

    /// What there is to do while nobody is here: join the liveliest nearby
    /// location channel, or look for notes left at this place.
    @ViewBuilder
    private var actions: some View {
        if let conversation = nearbyConversation {
            conversationHint(conversation)
        }
        if showsCheckNotesHint {
            checkNotesHint
        }
    }

    /// The radar with today's tally as its caption: the stat belongs to
    /// the scanning visual.
    private var radarBlock: some View {
        VStack(spacing: 8) {
            MeshRadarView(height: compact ? 56 : 112)
            if sightingsTracker.todayCount > 0 {
                Text(verbatim: sightingsText)
                    .font(.footnote)
                    .foregroundColor(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension MeshEmptyStateView {
    var nearbyConversation: NearbyConversation? {
        activityTracker.mostActiveConversation(among: locationChannelsModel.availableChannels)
    }

    /// Tap-to-reveal: the nearby-notes counter never subscribes on its own —
    /// looking at the mesh timeline must not open a building-precision relay
    /// REQ (a passive location side-channel). This static line is the one
    /// explicit act that unlocks it; nothing touches the network until the
    /// tap. It only renders when location permission is already granted
    /// (the tap never prompts, so without permission it would dead-end
    /// silently). Once revealed it yields to today's live strip and count,
    /// and the app-info setting stays the kill switch.
    var showsCheckNotesHint: Bool {
        nearbyNotes.offersRevealHint(permissionState: locationChannelsModel.permissionState)
    }

    var checkNotesHint: some View {
        Button {
            NearbyNotesCounter.shared.reveal()
        } label: {
            Label(Strings.checkNotes, systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    var sightingsText: String {
        sightingsTracker.todayCount == 1
            ? Strings.sightingsOne
            : Strings.sightingsMany(sightingsTracker.todayCount)
    }

    func conversationHint(_ conversation: NearbyConversation) -> some View {
        let headline = conversation.messageCount == 1
            ? Strings.activityOne(conversation.channel.geohash)
            : Strings.activityMany(conversation.channel.geohash)

        return Button {
            locationChannelsModel.markTeleported(for: conversation.channel.geohash, false)
            locationChannelsModel.select(.location(conversation.channel))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primary)
                    Text(verbatim: previewText(for: conversation.lastMessage))
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 420)
            .background(Color.novaSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.novaHairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    func previewText(for message: GeohashChatPreview) -> String {
        let maxLen = TransportConfig.uiGeoNotifySnippetMaxLen
        var content = message.content
        if content.count > maxLen {
            content = String(content.prefix(maxLen)) + "…"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let ago = formatter.localizedString(for: message.timestamp, relativeTo: Date())
        return "\(message.senderName): \(content) · \(ago)"
    }
}

/// The centered heart of an empty conversation, as the system's empty
/// states lay it out: a symbol or picture, a title, and a short message
/// under it.
struct ChatEmptyStateHeader<Visual: View>: View {
    let title: String
    let message: String
    @ViewBuilder let visual: () -> Visual

    @ThemedPalette private var palette

    var body: some View {
        VStack(spacing: 16) {
            visual()
            VStack(spacing: 6) {
                Text(verbatim: title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: message)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 24)
    }
}

/// A large symbol for an empty state, in the secondary color.
struct ChatEmptyStateSymbol: View {
    let systemImage: String

    @ThemedPalette private var palette

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(palette.secondary)
            .frame(height: 64)
            .accessibilityHidden(true)
    }
}
