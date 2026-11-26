//
// PersonActions.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// Someone a person row's actions act on: who they are and what the menu
/// may offer for them (`ConversationInfoPolicy.personActions(for:)`).
struct PersonActionTarget: Equatable {
    enum Identity: Equatable {
        /// A mesh peer, by peer ID.
        case mesh(PeerID)
        /// A location channel person, by their full Nostr public key.
        case nostr(pubkeyHex: String)
        /// The person of a geohash DM, by the DM's key, which maps to their
        /// Nostr key.
        case geohashDM(PeerID)
    }

    let identity: Identity
    let displayName: String
    let facts: ConversationInfoPolicy.ListedPerson

    var actions: [ConversationInfoPolicy.PersonAction] {
        ConversationInfoPolicy.personActions(for: facts)
    }
}

extension PersonActionTarget {
    /// A mesh peer of the roster.
    @MainActor
    init(meshPeer peer: MeshPeerRow, model: ConversationUIModel) {
        self.init(
            identity: .mesh(peer.peerID),
            displayName: peer.displayName,
            facts: ConversationInfoPolicy.ListedPerson(
                isMe: peer.isMe,
                hasMeshIdentity: true,
                isFavorite: peer.isFavorite,
                isBlocked: peer.isBlocked,
                canCreateGroup: !peer.isMe && model.canCreateGroup(with: peer.peerID)
            )
        )
    }

    /// Someone seen in the location channel.
    init(geohashPerson person: GeohashPersonRow) {
        self.init(
            identity: .nostr(pubkeyHex: person.id),
            displayName: person.displayName,
            facts: ConversationInfoPolicy.ListedPerson(
                isMe: person.isMe,
                hasMeshIdentity: false,
                isFavorite: false,
                isBlocked: person.isBlocked,
                canCreateGroup: false
            )
        )
    }
}

/// Runs a person action. The host (`personActionsHost()`) provides it, so
/// a row deep in a list can ask for a confirmation or a prompt.
struct PersonActionsHandler {
    let perform: @MainActor (ConversationInfoPolicy.PersonAction, PersonActionTarget) -> Void
}

private struct PersonActionsHandlerKey: EnvironmentKey {
    static let defaultValue: PersonActionsHandler? = nil
}

extension EnvironmentValues {
    var personActions: PersonActionsHandler? {
        get { self[PersonActionsHandlerKey.self] }
        set { self[PersonActionsHandlerKey.self] = newValue }
    }
}

extension View {
    /// Runs the person actions of the rows inside: favorite and unblock at
    /// once, block after a confirmation, and a new group after the name
    /// prompt of the message sender sheet.
    func personActionsHost() -> some View {
        modifier(PersonActionsHost())
    }

    /// The person actions as a context menu (long press, right click), as
    /// swipe actions on iOS (favorite leading, block trailing) and as
    /// VoiceOver actions. Needs `personActionsHost()` around it; a row with
    /// no target or no possible action gets none.
    func personActions(for target: PersonActionTarget?) -> some View {
        modifier(PersonActionsMenu(target: target))
    }
}

private struct PersonActionsHost: ViewModifier {
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var peerListModel: PeerListModel

    @State private var pendingBlock: PersonActionTarget?
    @State private var pendingGroup: PersonActionTarget?
    @State private var groupName = ""

    func body(content: Content) -> some View {
        content
            .environment(\.personActions, PersonActionsHandler { action, target in
                perform(action, on: target)
            })
            .confirmationDialog(
                Text(verbatim: PersonActionStrings.blockTitle(pendingBlock?.displayName ?? "")),
                isPresented: Binding(
                    get: { pendingBlock != nil },
                    set: { if !$0 { pendingBlock = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    if let target = pendingBlock {
                        block(target)
                    }
                    pendingBlock = nil
                } label: {
                    Text(verbatim: PersonActionStrings.block)
                }
                Button("common.cancel", role: .cancel) {
                    pendingBlock = nil
                }
            } message: {
                Text(verbatim: PersonActionStrings.blockMessage)
            }
            .alert(
                "group.create.title",
                isPresented: Binding(
                    get: { pendingGroup != nil },
                    set: { if !$0 { pendingGroup = nil } }
                )
            ) {
                TextField("group.create.name", text: $groupName)
                Button("common.cancel", role: .cancel) {
                    pendingGroup = nil
                }
                Button("group.create.action") {
                    // Opens the new group's chat.
                    if let target = pendingGroup, case .mesh(let peerID) = target.identity {
                        _ = conversationUIModel.createGroup(named: groupName, inviting: peerID)
                    }
                    pendingGroup = nil
                }
            } message: {
                Text("group.create.prompt")
            }
    }

    private func perform(_ action: ConversationInfoPolicy.PersonAction, on target: PersonActionTarget) {
        // The policy decided the action applies; check it again, as the
        // person may have changed since the menu was built.
        guard target.actions.contains(action) else { return }
        switch action {
        case .favorite, .unfavorite:
            if case .mesh(let peerID) = target.identity {
                peerListModel.toggleFavorite(peerID: peerID)
            }
        case .createGroup:
            groupName = GroupManagementPolicy.defaultName(with: target.displayName)
            pendingGroup = target
        case .block:
            pendingBlock = target
        case .unblock:
            unblock(target)
        }
    }

    private func block(_ target: PersonActionTarget) {
        switch target.identity {
        case .mesh(let peerID), .geohashDM(let peerID):
            conversationUIModel.block(peerID: peerID, displayName: target.displayName)
        case .nostr(let pubkeyHex):
            peerListModel.blockGeohashUser(pubkeyHexLowercased: pubkeyHex.lowercased(), displayName: target.displayName)
        }
    }

    private func unblock(_ target: PersonActionTarget) {
        switch target.identity {
        case .mesh(let peerID):
            conversationUIModel.unblock(peerID: peerID, displayName: target.displayName)
        case .nostr(let pubkeyHex):
            peerListModel.unblockGeohashUser(pubkeyHexLowercased: pubkeyHex.lowercased(), displayName: target.displayName)
        case .geohashDM:
            // A geohash block removes the DM, so no page offers this.
            break
        }
    }
}

private struct PersonActionsMenu: ViewModifier {
    @Environment(\.personActions) private var handler
    let target: PersonActionTarget?

    func body(content: Content) -> some View {
        if let target, let handler, !target.actions.isEmpty {
            let actions = target.actions
            content
                .contextMenu {
                    ForEach(actions, id: \.self) { action in
                        menuButton(action, target: target, handler: handler)
                    }
                }
                #if os(iOS)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    ForEach(actions.filter { $0 == .favorite || $0 == .unfavorite }, id: \.self) { action in
                        swipeButton(action, target: target, handler: handler)
                            .tint(.yellow)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Tint, not the destructive role: that role animates the
                    // row away, and a blocked person stays listed.
                    ForEach(actions.filter { $0 == .block || $0 == .unblock }, id: \.self) { action in
                        swipeButton(action, target: target, handler: handler)
                            .tint(action == .block ? .red : .gray)
                    }
                }
                #endif
                .accessibilityActions {
                    ForEach(actions, id: \.self) { action in
                        Button(PersonActionStrings.title(for: action, name: target.displayName)) {
                            handler.perform(action, target)
                        }
                    }
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private func menuButton(
        _ action: ConversationInfoPolicy.PersonAction,
        target: PersonActionTarget,
        handler: PersonActionsHandler
    ) -> some View {
        let title = PersonActionStrings.title(for: action, name: target.displayName)
        if action == .block {
            Button(role: .destructive) {
                handler.perform(action, target)
            } label: {
                Label(title, systemImage: PersonActionStrings.systemImage(for: action))
            }
        } else {
            Button {
                handler.perform(action, target)
            } label: {
                Label(title, systemImage: PersonActionStrings.systemImage(for: action))
            }
        }
    }

    private func swipeButton(
        _ action: ConversationInfoPolicy.PersonAction,
        target: PersonActionTarget,
        handler: PersonActionsHandler
    ) -> some View {
        Button {
            handler.perform(action, target)
        } label: {
            Label(
                PersonActionStrings.title(for: action, name: target.displayName),
                systemImage: PersonActionStrings.systemImage(for: action)
            )
        }
    }
}

enum PersonActionStrings {
    static let favorite = String(localized: "conversation_info.person.favorite", defaultValue: "Add to Favorites", comment: "Menu action on a person in a channel's or group's people list, and on a DM's details page, that adds them to favorites")
    static let unfavorite = String(localized: "conversation_info.person.unfavorite", defaultValue: "Remove from Favorites", comment: "Menu action on a person in a channel's or group's people list, and on a DM's details page, that removes them from favorites")
    static let block = String(localized: "conversation_info.person.block", defaultValue: "Block", comment: "Menu action that blocks a person, and the button that confirms it")
    static let unblock = String(localized: "conversation_info.person.unblock", defaultValue: "Unblock", comment: "Menu action that unblocks a person")
    static let blockMessage = String(localized: "conversation_info.block.message", defaultValue: "You will no longer see their messages. You can unblock them in Settings.", comment: "Message of the confirmation before blocking a person from their details page")

    static func blockTitle(_ name: String) -> String {
        String(
            format: String(localized: "conversation_info.block.confirm", defaultValue: "Block %@?", comment: "Title of the confirmation before blocking a person from their details page; placeholder is their name"),
            locale: .current,
            name
        )
    }

    static func createGroup(with name: String) -> String {
        String(
            format: String(localized: "conversation_info.person.create_group", defaultValue: "Create Group With %@", comment: "Menu action on a person in a people list that starts a new group with them; placeholder is their name"),
            locale: .current,
            name
        )
    }

    static func title(for action: ConversationInfoPolicy.PersonAction, name: String) -> String {
        switch action {
        case .favorite: favorite
        case .unfavorite: unfavorite
        case .createGroup: createGroup(with: name)
        case .block: block
        case .unblock: unblock
        }
    }

    static func systemImage(for action: ConversationInfoPolicy.PersonAction) -> String {
        switch action {
        case .favorite: "star"
        case .unfavorite: "star.slash"
        case .createGroup: "person.3"
        case .block: "nosign"
        case .unblock: "checkmark.circle"
        }
    }
}
