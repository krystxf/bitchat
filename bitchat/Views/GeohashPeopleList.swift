import SwiftUI

/// The people section of a location channel: everyone seen in the geohash,
/// people physically here first, then those who teleported in. Tapping a
/// row opens a geohash DM. Block and unblock live in the swipe actions and
/// the context menu.
struct GeohashPeopleList: View, Equatable {
    @EnvironmentObject private var peerListModel: PeerListModel
    @ThemedPalette private var palette
    /// The channel's geohash, shown as the section header.
    var geohash: String? = nil
    /// The people sheet bumps this after it rebuilds the roster on open. A
    /// new value drops the remembered row order, so the sheet opens with the
    /// most recently active people first.
    var orderGeneration = 0
    let onTapPerson: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var orderMemory = PeopleListOrderMemory()

    /// The tap action always reveals the DM pane and can't be compared.
    /// Treating it as equal lets SwiftUI skip this section when the
    /// presenting view re-renders for models the section doesn't read
    /// (message batches, chrome, verification); roster changes still arrive
    /// through the observed PeerListModel.
    nonisolated static func == (lhs: GeohashPeopleList, rhs: GeohashPeopleList) -> Bool {
        lhs.geohash == rhs.geohash && lhs.orderGeneration == rhs.orderGeneration
    }

    private enum Strings {
        static let youSuffix: LocalizedStringKey = "geohash_people.you_suffix"
        static let blockedTooltip = String(localized: "geohash_people.tooltip.blocked", comment: "Tooltip shown next to users blocked in geohash channels")
        static let unblock = String(localized: "geohash_people.action.unblock", comment: "Context menu action to unblock a person")
        static let block = String(localized: "geohash_people.action.block", comment: "Context menu action to block a person")
        static let teleported = String(localized: "geohash_people.state.teleported", comment: "State label for someone who joined the location channel from elsewhere")
        static let nearby = String(localized: "geohash_people.state.nearby", comment: "State label for someone physically in the location channel's area")
        static let blockedState = String(localized: "mesh_peers.state.blocked", comment: "State label for a blocked peer")
        static let youState = String(localized: "geohash_people.state.you", comment: "State label marking your own row in the people list")
        static let openDMHint = String(localized: "mesh_peers.accessibility.open_dm_hint", comment: "Accessibility hint on a peer row explaining activation opens a private chat")
    }

    var body: some View {
        let people = peerListModel.geohashPeople
        let personByID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let displayed = orderMemory.order(people.map(\.id), generation: orderGeneration)
            .compactMap { personByID[$0] }
        // People physically here first, then those who teleported in.
        let rows = displayed.filter { !$0.isTeleported } + displayed.filter(\.isTeleported)

        Section {
            if rows.isEmpty {
                PeopleEmptyRow()
            } else {
                // The list builds only the visible rows, so a busy room with
                // hundreds of people stays cheap.
                ForEach(rows) { person in
                    if person.isMe {
                        rowContent(for: person)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(accessibilityDescription(for: person))
                    } else {
                        personRow(for: person)
                    }
                }
            }
        } header: {
            if let geohash {
                Text(verbatim: "#\(geohash.lowercased())")
            }
        }
    }

    private func personRow(for person: GeohashPersonRow) -> some View {
        Button {
            peerListModel.openGeohashDirectMessage(with: person.id)
            onTapPerson()
        } label: {
            rowContent(for: person)
        }
        .peopleRowButtonStyle()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Tint, not the destructive role: a destructive swipe action
            // animates the row away, and a blocked person stays listed.
            blockButton(for: person)
                .tint(person.isBlocked ? .gray : .red)
        }
        .contextMenu {
            blockButton(for: person)
        }
        .accessibilityLabel(accessibilityDescription(for: person))
        .accessibilityHint(Strings.openDMHint)
        .accessibilityActions {
            Button(person.isBlocked ? Strings.unblock : Strings.block) {
                toggleBlock(person)
            }
        }
    }

    private func blockButton(for person: GeohashPersonRow) -> some View {
        Button {
            toggleBlock(person)
        } label: {
            Label(
                person.isBlocked ? Strings.unblock : Strings.block,
                systemImage: person.isBlocked ? "checkmark.circle" : "nosign"
            )
        }
    }

    private func toggleBlock(_ person: GeohashPersonRow) {
        if person.isBlocked {
            peerListModel.unblockGeohashUser(
                pubkeyHexLowercased: person.id,
                displayName: person.displayName
            )
        } else {
            peerListModel.blockGeohashUser(
                pubkeyHexLowercased: person.id,
                displayName: person.displayName
            )
        }
    }

    private func rowContent(for person: GeohashPersonRow) -> some View {
        let color: Color = person.isMe
            ? .orange
            : peerListModel.colorForGeohashPerson(id: person.id, isDark: colorScheme == .dark)
        return PeopleRow(
            systemImage: person.isTeleported ? "face.dashed" : "mappin.and.ellipse",
            iconColor: color,
            subtitle: person.isTeleported ? Strings.teleported : Strings.nearby
        ) {
            HStack(spacing: 0) {
                PeopleRowName(name: person.displayName, isEmphasized: person.isMe)
                if person.isMe {
                    Text(Strings.youSuffix)
                        .foregroundColor(palette.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } accessories: {
            if person.isBlocked {
                Image(systemName: "nosign")
                    .foregroundColor(.red)
                    .help(Strings.blockedTooltip)
            }
        }
    }

    /// One spoken sentence per row: name, presence type, and block state.
    private func accessibilityDescription(for person: GeohashPersonRow) -> String {
        var parts: [String] = [person.displayName]
        if person.isMe { parts.append(Strings.youState) }
        parts.append(person.isTeleported ? Strings.teleported : Strings.nearby)
        if person.isBlocked { parts.append(Strings.blockedState) }
        return parts.joined(separator: ", ")
    }
}
