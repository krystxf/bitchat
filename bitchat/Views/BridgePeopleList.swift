//
// BridgePeopleList.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The people-sheet section for participants visible across the mesh bridge:
/// same place, beyond radio range. Display-only in v1 — bridged identities
/// are per-cell rendezvous keys with no DM route yet, so the rows have no
/// tap or actions.
struct BridgePeopleList: View {
    @ObservedObject private var bridgeService = BridgeService.shared

    private enum Strings {
        static let sectionTitle = String(localized: "bridge_people.section_title", defaultValue: "across the bridge", comment: "Section header in the people sheet for participants reachable via the mesh bridge")
        static let rowHint = String(localized: "bridge_people.accessibility.row_hint", defaultValue: "In your area, connected through the bridge", comment: "Accessibility hint for a person listed in the bridge section of the people sheet")
    }

    var body: some View {
        // Not gated on the toggle: bridged people arrive over passive radio
        // (a serving neighbor's carriers) even while this device's own
        // bridge is off — whoever is visible in the timeline belongs in the
        // sheet.
        if !bridgeService.bridgedParticipants.isEmpty {
            Section {
                ForEach(bridgeService.bridgedParticipants) { person in
                    PeopleRow(systemImage: "network", iconColor: Color.cyan) {
                        PeopleRowName(name: person.displayName)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(person.displayName)
                    .accessibilityHint(Strings.rowHint)
                }
            } header: {
                Text(verbatim: Strings.sectionTitle)
            }
        }
    }
}
